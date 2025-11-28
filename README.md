# ⚡ Zama Private Reaction Test

**Press when it turns green. The blockchain only sees your performance tier — never your raw milliseconds.**

A fully homomorphic encryption (FHE) demo built on **Zama FHEVM**, showcasing how real-time encrypted inputs can be processed entirely on-chain without revealing private data.

---

## 🎯 Overview

**Private Reaction Test** is a browser-based mini-game that measures your reaction time locally, encrypts the result with Zama's **Relayer SDK**, and sends the ciphertext to an **FHE-enabled smart contract** deployed on the **Sepolia FHEVM** network.

The contract never learns your exact milliseconds — it only evaluates which **category** (Gold / Silver / Bronze) your encrypted reaction belongs to, using FHE comparisons.

---

## 🔐 Model of Operation

### 1. Local Measurement

* The frontend displays a simple light signal (red → green).
* When the screen turns green, the user clicks as fast as possible.
* The browser measures the reaction time in **milliseconds**.

### 2. Encryption (Client-Side)

* The measured value (e.g., `2784 ms`) is **encrypted inside the browser** using the [Zama Relayer SDK](https://docs.zama.ai/protocol/relayer-sdk-guides/).
* The user’s browser generates `externalEuint16` ciphertext and `proof` via `createEncryptedInput(...)`.

### 3. FHE Evaluation (Smart Contract)

* The encrypted time is submitted to the contract:

  ```solidity
  submitEncryptedReaction(bytes32 encTime, bytes proof)
  ```
* The contract compares the ciphertext to three encrypted thresholds:

  ```solidity
  ebool gold = FHE.le(encTime, eGoldThreshold);
  ebool silver = FHE.le(encTime, eSilverThreshold);
  ebool bronze = FHE.le(encTime, eBronzeThreshold);
  ```
* Only the **tier category** (Gold/Silver/Bronze) remains, stored as encrypted output (`eTier`).
* The raw time never leaves the browser or appears on-chain.

### 4. Decryption (User-Side)

* Using **userDecrypt** (EIP-712 + Relayer flow), the user decrypts their result locally.
* The chain only stores encrypted values and access rights — no plaintexts are ever public.

---

## 🧠 Smart Contract Logic

Contract address: `0x336AD8895440fB523EEA1573A8f13c0d7C5aE130`

The contract uses Zama’s official Solidity library:

```solidity
import { FHE, euint16, ebool, externalEuint16 } from "@fhevm/solidity/lib/FHE.sol";
```

### Core Features

* **Encrypted thresholds:** Gold, Silver, and Bronze limits are stored as encrypted `euint16` values.
* **Encrypted input:** Users send their reaction time encrypted off-chain.
* **FHE comparison:** Contract compares encrypted time vs encrypted thresholds using `FHE.le()`.
* **Encrypted tier result:** Output is stored as `euint16 eTier`, decryptable only by the player.

### Admin Flow

Only the contract owner can configure thresholds:

```solidity
setReactionTiers(encGold, encSilver, encBronze, proof);
```

Each threshold is encrypted client-side with the Relayer SDK, ensuring even admin data stays private.

---

## 💻 User Interface & Usage

### 1. 🦊 Connect Your Wallet

* Click **Connect Wallet** (MetaMask or any EIP-1193 provider).
* The app auto-switches to **Sepolia FHEVM**.

### 2. 🚦 Start a Reaction Test

* Click **Start new reaction test**.
* Wait for the light to turn **green**, then tap the circle.
* The app measures your reaction time locally (in ms).

### 3. 🔐 Encrypt & Send

* Click **Encrypt & send to contract**.
* The time is encrypted and sent to the FHEVM contract.
* Smart contract evaluates your encrypted performance tier (Gold / Silver / Bronze).

### 4. 🏅 View Your Private Result

* Click **Refresh & decrypt last result**.
* The app uses `userDecrypt()` to retrieve and decrypt your encrypted tier.
* The chain never sees or stores your plaintext reaction time.

### 5. 🛠 Admin Panel (Owner Only)

* Visible only to the contract owner.
* Allows encrypted configuration of thresholds (Gold/Silver/Bronze) in milliseconds.
* Thresholds are encrypted locally before being sent to the contract.

---

## 🧩 Project Structure

```
Zama-Private-Reaction-Test/
├── index.html          # One-page webapp (UI + logic + Relayer integration)
├── /assets/            # Optional static icons or backgrounds
├── README.md           # Project documentation
└── /contracts/         # Solidity source (for reference)
```

### Key Frontend Modules

| Section                     | Description                                              |
| --------------------------- | -------------------------------------------------------- |
| `fheCore.configure()`       | Initializes FHE Relayer + contract connection            |
| `encryptUint16(value)`      | Encrypts user reaction time locally                      |
| `submitEncryptedReaction()` | Sends ciphertext + proof to FHEVM                        |
| `userDecryptHandles()`      | Performs user-side decryption via Relayer SDK            |
| `setReactionTiers()`        | Owner-only: sets encrypted Gold/Silver/Bronze thresholds |

---

## ⚙️ Tech Stack

* **Smart Contract:** Solidity 0.8.24 on Zama FHEVM (Sepolia)
* **Frontend:** HTML + Vanilla JS (no frameworks)
* **Encryption Layer:** [@zama-fhe/relayer-sdk](https://cdn.zama.org/relayer-sdk-js/0.3.0-5/relayer-sdk-js.js)
* **Web3 Library:** ethers.js v6.15

---

## 🧩 Core Concepts Demonstrated

| Concept                   | Description                                                                          |
| ------------------------- | ------------------------------------------------------------------------------------ |
| **FHE Encrypted Inputs**  | All values (reaction times, thresholds) are encrypted before reaching the blockchain |
| **Encrypted Computation** | Smart contract computes comparisons (`<`, `>`, `=`) directly on ciphertexts          |
| **Private Decryption**    | Only the user can decrypt their own category via EIP-712-signed userDecrypt          |
| **On-chain Privacy**      | No plaintexts (milliseconds or thresholds) ever appear on-chain                      |

---

## 🏁 Summary

**Zama Private Reaction Test** proves that even simple games can be built on privacy-preserving blockchain logic. Every reaction, threshold, and result remains **fully encrypted**, showing the power of **Zama’s FHEVM** for secure, real-time computation.

> “Play fast, stay private.”
