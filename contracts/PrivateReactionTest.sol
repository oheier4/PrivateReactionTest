// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {
  FHE,
  ebool,
  euint8,
  euint16,
  externalEuint16
} from "@fhevm/solidity/lib/FHE.sol";

import { ZamaEthereumConfig } from "@fhevm/solidity/config/ZamaConfig.sol";

contract PrivateReactionTest is ZamaEthereumConfig {
  // ---------------------------------------------------------------------------
  // Ownership
  // ---------------------------------------------------------------------------

  address public owner;

  modifier onlyOwner() {
    require(msg.sender == owner, "Not owner");
    _;
  }

  constructor() {
    owner = msg.sender;
  }

  function transferOwnership(address newOwner) external onlyOwner {
    require(newOwner != address(0), "zero owner");
    owner = newOwner;
  }

  // ---------------------------------------------------------------------------
  // Simple nonReentrant guard
  // ---------------------------------------------------------------------------

  uint256 private _locked = 1;

  modifier nonReentrant() {
    require(_locked == 1, "reentrancy");
    _locked = 2;
    _;
    _locked = 1;
  }

  // ---------------------------------------------------------------------------
  // Global encrypted tier configuration
  // ---------------------------------------------------------------------------

  /**
   * @dev Encrypted global thresholds (in milliseconds).
   *
   * Interpretation (recommended off-chain convention):
   *  - eMaxGoldMs   : reaction <= eMaxGoldMs   => Gold
   *  - eMaxSilverMs : reaction <= eMaxSilverMs => Silver (if not Gold)
   *  - eMaxBronzeMs : reaction <= eMaxBronzeMs => Bronze (if not Silver/Gold)
   *
   * Developers should encrypt thresholds such that:
   *    Gold <= Silver <= Bronze   (smaller is better)
   *
   * The contract cannot check this ordering on-chain because thresholds
   * are encrypted.
   */
  struct TierConfig {
    bool initialized;
    euint16 eMaxGoldMs;
    euint16 eMaxSilverMs;
    euint16 eMaxBronzeMs;
  }

  TierConfig private _tiers;

  event TiersConfigured();

  /**
   * @notice Set or update encrypted thresholds for all players.
   *
   * @dev
   *  Frontend / admin flow:
   *    1) Use Relayer SDK (`createEncryptedInput`) to encrypt three
   *       uint16 values: maxGoldMs, maxSilverMs, maxBronzeMs.
   *    2) Ask the Gateway to produce three `externalEuint16` handles
   *       plus a shared attestation `proof`.
   *    3) Call `setReactionTiers(...)` with these values.
   *
   *  NOTE: Thresholds are GLOBAL and apply to all players.
   */
  function setReactionTiers(
    externalEuint16 encMaxGoldMs,
    externalEuint16 encMaxSilverMs,
    externalEuint16 encMaxBronzeMs,
    bytes calldata proof
  ) external onlyOwner {
    require(proof.length != 0, "missing proof");

    TierConfig storage T = _tiers;
    T.initialized = true;

    // Ingest encrypted thresholds and give the contract permanent rights.
    euint16 tmp;

    tmp = FHE.fromExternal(encMaxGoldMs, proof);
    FHE.allowThis(tmp);
    T.eMaxGoldMs = tmp;

    tmp = FHE.fromExternal(encMaxSilverMs, proof);
    FHE.allowThis(tmp);
    T.eMaxSilverMs = tmp;

    tmp = FHE.fromExternal(encMaxBronzeMs, proof);
    FHE.allowThis(tmp);
    T.eMaxBronzeMs = tmp;

    emit TiersConfigured();
  }

  /**
   * @notice Owner-only helper to inspect encrypted threshold handles.
   * @dev    Only handles are returned; raw values remain confidential.
   */
  function getTierPolicyHandles()
    external
    view
    onlyOwner
    returns (
      bytes32 maxGoldHandle,
      bytes32 maxSilverHandle,
      bytes32 maxBronzeHandle,
      bool initialized
    )
  {
    TierConfig storage T = _tiers;
    return (
      FHE.toBytes32(T.eMaxGoldMs),
      FHE.toBytes32(T.eMaxSilverMs),
      FHE.toBytes32(T.eMaxBronzeMs),
      T.initialized
    );
  }

  // ---------------------------------------------------------------------------
  // Player reaction results
  // ---------------------------------------------------------------------------

  /**
   * @dev Encodes encrypted reaction time and tier for a player.
   *
   *  - eReactionMs   : encrypted reaction time in milliseconds (euint16).
   *  - eTier         : encrypted tier code (euint8: 0..3).
   *  - decided       : true once at least one reaction has been recorded.
   *  - categoryPublic: true if the user opted into making eTier publicly
   *                    decryptable via `makeMyCategoryPublic`.
   */
  struct PlayerResult {
    euint16 eReactionMs;
    euint8  eTier;
    bool    decided;
    bool    categoryPublic;
  }

  mapping(address => PlayerResult) private _results;

  event ReactionEvaluated(
    address indexed player,
    bytes32 categoryHandle
  );

  event CategoryMadePublic(
    address indexed player,
    bytes32 categoryHandle
  );

  /**
   * @notice Submit an encrypted reaction time for the caller.
   *
   * @dev
   *  Frontend flow (off-chain, using @zama-fhe/relayer-sdk):
   *
   *    1) Game measures reaction time in ms (uint16).
   *    2) SDK:
   *         - `const instance = await createInstance(SepoliaConfig | mainnetConfig, ...);`
   *         - `const input = instance.createEncryptedInput(userAddress);`
   *         - `input.add64(reactionTimeMs);` (or appropriate add16/add32 helper)
   *         - Send to Gateway, get `externalEuint16` + `proof`.
   *    3) Call `submitEncryptedReaction(encReactionMs, proof)` from the user wallet.
   *
   *  The contract:
   *    - compares the encrypted reaction time against encrypted global thresholds,
   *    - computes an encrypted tier code (0/1/2/3),
   *    - stores both encrypted time and tier,
   *    - grants the user decryption rights on their encrypted tier (and optionally time),
   *    - emits an event with the encrypted tier handle only.
   */
  function submitEncryptedReaction(
    externalEuint16 encReactionMs,
    bytes calldata proof
  ) external nonReentrant {
    require(_tiers.initialized, "Tiers not configured");
    require(proof.length != 0, "proof required");

    PlayerResult storage R = _results[msg.sender];

    // Ingest encrypted reaction time from Gateway.
    euint16 eMs = FHE.fromExternal(encReactionMs, proof);

    // Long-term ACL for the contract and the player.
    FHE.allowThis(eMs);
    FHE.allow(eMs, msg.sender);

    // -----------------------------------------------------------------------
    // Encrypted tier computation
    // -----------------------------------------------------------------------
    //
    // Tier encoding:
    //   0 = None
    //   1 = Bronze
    //   2 = Silver
    //   3 = Gold
    //
    // Logic (in plaintext terms), assuming:
    //   Gold <= Silver <= Bronze
    //
    //   if ms <= maxGold   => Gold (3)
    //   else if ms <= maxSilver => Silver (2)
    //   else if ms <= maxBronze => Bronze (1)
    //   else => None (0)
    //
    // We implement this using encrypted comparisons + FHE.select.
    //
    TierConfig storage T = _tiers;

    ebool leGold   = FHE.le(eMs, T.eMaxGoldMs);
    ebool leSilver = FHE.le(eMs, T.eMaxSilverMs);
    ebool leBronze = FHE.le(eMs, T.eMaxBronzeMs);

    // Constant encrypted tier codes
    euint8 tierNone   = FHE.asEuint8(0);
    euint8 tierBronze = FHE.asEuint8(1);
    euint8 tierSilver = FHE.asEuint8(2);
    euint8 tierGold   = FHE.asEuint8(3);

    // Base: if ms <= bronze => Bronze, else None
    euint8 eBase = FHE.select(leBronze, tierBronze, tierNone);
    // If ms <= silver, override with Silver
    euint8 eAfterSilver = FHE.select(leSilver, tierSilver, eBase);
    // If ms <= gold, override with Gold (fastest tier wins)
    euint8 eFinalTier = FHE.select(leGold, tierGold, eAfterSilver);

    // Persist encrypted state
    R.eReactionMs   = eMs;
    R.eTier         = eFinalTier;
    R.decided       = true;
    R.categoryPublic = false;

    // Ensure contract retains long-term ACL on stored ciphertexts.
    FHE.allowThis(R.eReactionMs);
    FHE.allowThis(R.eTier);

    // Allow user to privately decrypt their own result.
    FHE.allow(R.eTier, msg.sender);
    FHE.allow(R.eReactionMs, msg.sender);

    emit ReactionEvaluated(
      msg.sender,
      FHE.toBytes32(R.eTier)
    );
  }

  // ---------------------------------------------------------------------------
  // Optional: user opt-in public category (for bragging rights / leaderboards)
  // ---------------------------------------------------------------------------

  /**
   * @notice Turn the caller's tier into a publicly decryptable value.
   *
   * @dev
   *  After calling this:
   *    - Anyone can use Relayer SDK `publicDecrypt(handle)` to recover the
   *      cleartext tier code (0..3), with on-chain verifiable signatures.
   *    - This is irreversible from a privacy standpoint.
   */
  function makeMyCategoryPublic() external nonReentrant {
    PlayerResult storage R = _results[msg.sender];
    require(R.decided, "No reaction recorded");

    // Ensure contract has rights, then flip ACL flag for global decryption.
    FHE.allowThis(R.eTier);
    FHE.makePubliclyDecryptable(R.eTier);

    R.categoryPublic = true;

    emit CategoryMadePublic(
      msg.sender,
      FHE.toBytes32(R.eTier)
    );
  }

  // ---------------------------------------------------------------------------
  // Getters (handles only, no FHE ops)
  // ---------------------------------------------------------------------------

  /**
   * @notice Get the encrypted tier handle for the caller.
   *
   * @return tierHandle  Encrypted tier code (0..3). Use `userDecrypt(...)`
   *                     off-chain to reveal it privately.
   * @return decided     True if at least one reaction has been processed.
   */
  function getMyCategoryHandle()
    external
    view
    returns (bytes32 tierHandle, bool decided)
  {
    PlayerResult storage R = _results[msg.sender];
    return (FHE.toBytes32(R.eTier), R.decided);
  }

 
  function getPlayerMeta(address player)
    external
    view
    returns (bool decided, bool categoryPublic)
  {
    PlayerResult storage R = _results[player];
    return (R.decided, R.categoryPublic);
  }

  
  function getPublicCategoryHandle(address player)
    external
    view
    returns (bytes32 tierHandle, bool decided, bool categoryPublic)
  {
    PlayerResult storage R = _results[player];
    return (FHE.toBytes32(R.eTier), R.decided, R.categoryPublic);
  }
}
