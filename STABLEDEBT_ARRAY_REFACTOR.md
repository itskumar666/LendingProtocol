# StableDebtToken Array-Based Refactoring

## ✅ Completed: Production-Grade Architecture

You chose to build with **real protocol** architecture, not a simplified version. Here's what that means for StableDebtToken:

### Data Structure Change

**OLD (Simplified):**
```solidity
mapping(address => Debt) public userDebt;  // Only 1 debt per user
```

**NEW (Production-Grade):**
```solidity
mapping(address => Debt[]) public userDebts;  // Multiple debts per user
```

### Why This Matters

**Real-world scenario:**
```
Time 1: User borrows 100 USDC at 5% APY
  → userDebts[user] = [Debt(100, 5e2, timestamp1)]

Time 2: User borrows 50 USDC at 6% APY
  → userDebts[user] = [Debt(100, 5e2, timestamp1), Debt(50, 6e2, timestamp2)]

Time 3: User repays 120 USDC
  → First debt fully paid (100 paid)
  → Second debt partially paid (20 of 50 paid)
  → Result: [Debt(0, 5e2, timestamp1), Debt(30, 6e2, timestamp2)]
```

This is how **real lending protocols** work. AAVE uses this exact approach.

---

## 📋 Functions to Implement

### 1. **mint(user, amount, rate)** 
Array-based minting - append new debt, don't overwrite

```
Steps:
1. Validate: rate <= 1000e2, amount > 0
2. Create: Debt(uint128(amount), uint128(rate), block.timestamp)
3. Append: userDebts[user].push(debt)
4. Emit: DebtMinted(user, amount, rate)
```

---

### 2. **getDebtWithInterest(user)**
Calculate total debt with interest from ALL debts in array

```
Steps:
1. Loop through userDebts[user][] (may be 0, 1, 2, ... debts)
2. For each debt:
   - timeElapsed = block.timestamp - debt.timestamp
   - interest = (debt.amount × debt.rate × timeElapsed) / (31536000 × 100e2)
   - Add debt.amount + interest to total
3. Return total

Example:
- Debt 1: 100 @ 5% for 365 days → 100 + 5 = 105
- Debt 2: 50 @ 6% for 180 days → 50 + 1.5 = 51.5
- Total: 156.5
```

---

### 3. **burn(user, amount)**
FIFO repayment from array (oldest debt first)

```
Steps:
1. Get userDebts[user] array
2. Track remainingAmount = amount
3. Loop through array (FIFO):
   for i = 0 to length:
     if debt[i].amount == 0: skip
     if debt[i].amount >= remaining:
       debt[i].amount -= remaining
       remaining = 0
       break
     else:
       remaining -= debt[i].amount
       debt[i].amount = 0
4. Validate: if remaining > 0, revert (tried to overpay)
5. Emit: DebtBurned(user, amount)

Example:
- Start: [Debt(100), Debt(50)]
- Repay 120:
  - Pay 100 to debt[0] → [Debt(0), Debt(50)]
  - Pay 20 to debt[1] → [Debt(0), Debt(30)]
  - Finish with remaining = 0 ✓
```

---

### 4. **balanceOf(account)**
Simple delegation to get total debt with interest

```
Steps:
1. Call getDebtWithInterest(account)
2. Return the result
(That's it - just one line!)
```

---

### 5. **transfer() & transferFrom()**
Non-transferable - prevent debt trading

```solidity
// Both functions should:
revert("StableDebtToken: Cannot transfer debt");
```

---

## 🔑 Key Insights

### Why Array?
1. **Multiple borrows**: User can borrow multiple times at different rates
2. **Per-debt interest**: Each debt calculates interest independently
3. **Production realistic**: Matches how AAVE actually works

### Why FIFO (First-In-First-Out)?
- Most common repayment strategy
- Oldest debts repay first
- Clear, predictable ordering

### Simple vs Compound Interest?
We use **simple interest** (not compound):
- Formula: `interest = principal × rate × time / (1 year × 100e2)`
- Easier to calculate and understand
- No iterative compounding needed

---

## 📊 Formula Reference

### Interest Calculation
```
interest = (principal × rate × timeElapsed) / (365 × 86400 × 100e2)
         = (principal × rate × timeElapsed) / (31536000 × 100e2)

Where:
- principal = amount borrowed (in smallest units, e.g., wei)
- rate = APY × 100 (e.g., 5% = 5e2 = 500)
- timeElapsed = block.timestamp - debt.timestamp (in seconds)
```

### Seconds Per Year
```
365 days × 24 hours × 60 minutes × 60 seconds = 31,536,000 seconds
```

---

## 🎯 Next Steps

1. Implement `mint()` - append to array
2. Implement `getDebtWithInterest()` - loop + sum with interest
3. Implement `burn()` - FIFO loop logic
4. Implement `balanceOf()` - delegate to getDebtWithInterest
5. Implement `transfer()` / `transferFrom()` - revert

All functions have detailed TODO comments in the contract!

---

## ✨ Real Protocol Benefits

This array-based approach gives you:
- ✅ Multiple borrow positions per user
- ✅ Separate interest rates per borrow
- ✅ Clear repayment ordering (FIFO)
- ✅ Production-ready architecture
- ✅ AAVE-aligned design

You're building the **real thing**, not a dummy protocol! 🚀
