# 🧠 Hybrid Reward Staking Smart Contract

A **hybrid staking smart contract** built with Solidity that distributes rewards using a **balanced 70/30 model**:
- **70%** of rewards based on **activity (contribution points)**  
- **30%** of rewards based on **token holding (stake-time)**  

This contract ensures that both **active users** and **long-term holders** are rewarded fairly — promoting sustainable growth in token ecosystems.

---

## 🚀 Key Features

✅ **Hybrid Reward Model:**  
Automatically splits rewards into 70% activity-based and 30% holding-based pools.

✅ **Epoch-Based Distribution:**  
Rewards are distributed per epoch (a time-based cycle).

✅ **Stake & Unstake Anytime:**  
Users can freely stake or unstake tokens during the epoch.

✅ **Activity Integration:**  
Authorized managers can grant activity points (on-chain or off-chain verified).

✅ **Transparent & Fair:**  
All staking, activity, and claim data are publicly viewable on-chain.

✅ **Secure Ownership & Rescue Mechanism:**  
Only the owner can manage epochs and recover misplaced tokens.

---

## ⚙️ Smart Contract Details

| Parameter | Description |
|------------|--------------|
| **Language** | Solidity v0.8.19 |
| **License** | MIT |
| **Contract Name** | `HybridRewardStaking` |
| **Dependencies** | ERC20-compatible tokens |
| **Reward Distribution** | 70% Activity + 30% Holding |

---

## 🧩 How It Works

1. **Start Epoch:**  
   The contract owner starts an epoch by funding it with reward tokens and setting its duration.

2. **Users Stake:**  
   Users deposit tokens to earn holding (stake-time) points.

3. **Activity Points:**  
   Activity managers award activity points to active users (e.g., trading, governance, or ecosystem engagement).

4. **Claim Rewards:**  
   After an epoch ends, users claim their share of the reward pool based on:
   Reward = 70% * (userActivity / totalActivity) + 30% * (userHolding / totalHolding)
## 🧠 Example Scenario

- Epoch reward = 10,000 tokens  
- Total activity = 1,000 pts  
- Total holding = 500,000 stake-seconds  

| User | Activity | Holding | Reward (approx.) |
|------|-----------|----------|------------------|
| Alice | 100 pts | 100,000 | 1,600 tokens |
| Bob | 300 pts | 200,000 | 3,400 tokens |
| Carol | 600 pts | 200,000 | 5,000 tokens |

---

## 🧱 Deployment & Usage

### Prerequisites
- Token contracts must follow the ERC20 standard.
- The deployer must fund reward tokens before starting each epoch.

### Deployment Example
```solidity
constructor(address _stakeToken, address _rewardToken)
Basic Flow

stake(amount) → User stakes tokens.

awardActivity(user, points) → Manager assigns activity points.

startEpoch(rewardAmount, duration) → Owner starts a new reward period.

claim(epochId) → User claims rewards after epoch ends.


Disclaimer

This is a prototype contract for educational and demonstration purposes.
It has not been audited — deploy on testnets first.
Always perform security reviews before mainnet deployment.



MIT License

Copyright © 2025

You are free to use, modify, and distribute this software under the MIT License.
