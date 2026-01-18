## 🏗️ Building an AAVE-Like Lending Protocol from Scratch

This is a **learn-by-doing** project where you'll build a complete lending protocol (similar to AAVE V3) in Solidity + Foundry.

### 📚 Documentation Index (READ IN THIS ORDER)

1. **[START_HERE.md](docs/START_HERE.md)** ← BEGIN HERE
   - Your 7-day learning path
   - Phase-by-phase breakdown
   - Testing setup guide

2. **[QUICK_REFERENCE.md](docs/QUICK_REFERENCE.md)** ← KEEP OPEN WHILE CODING
   - 3 key concepts explained
   - All math formulas
   - Common pitfalls to avoid
   - Testing checklist

3. **[QUICK_START.md](docs/QUICK_START.md)** ← LEARN THE WHY
   - How lending protocols work
   - Core concepts (health factor, utilization, interest)
   - Implementation overview

4. **[DEVELOPMENT_ROADMAP.md](docs/DEVELOPMENT_ROADMAP.md)** ← DETAILED GUIDE
   - 6 phases of development
   - Every function explained
   - Logic to implement (no code, just concepts)
   - Step-by-step sequence

5. **[ALL_TODOS.md](docs/ALL_TODOS.md)** ← YOUR CHECKLIST
   - 40+ implementation items
   - Line-by-line breakdown
   - File organization

6. **[SECURITY.md](docs/SECURITY.md)** ← REFERENCE
   - Security checklist
   - Oracle integration
   - Edge cases to handle

### 🎯 Your First Week

```
Day 1-2: Implement AToken (interest-bearing token)
Day 3: Implement VariableDebtToken & StableDebtToken
Day 4-5: Implement LendingPool deposit/withdraw
Day 6-7: Implement health factor & borrowing logic
```

### 📁 Project Structure

```
src/
├── LendingPool.sol           (MAIN - implement last)
├── InterestRateStrategy.sol  (rate calculation)
└── tokens/
    ├── AToken.sol            (implement first)
    ├── VariableDebtToken.sol
    └── StableDebtToken.sol

test/
├── LendingPoolTest.sol       (examples provided)
└── ... (create your tests here)

docs/
├── START_HERE.md             (your roadmap)
├── QUICK_REFERENCE.md        (formulas & concepts)
├── QUICK_START.md            (deep dive)
├── DEVELOPMENT_ROADMAP.md    (detailed guide)
├── ALL_TODOS.md              (checklist)
└── SECURITY.md               (security guide)
```

### 🚀 Quick Start

```bash
# Clone and setup
cd /Users/ashutoshkumar/Desktop/LendingProtocol

# Run tests
forge test -vv

# See gas usage
forge test --gas-report
```

### 💡 Key Concepts You'll Learn

- **Interest-Bearing Tokens**: How deposits grow without minting new tokens
- **Health Factor**: The risk metric that prevents insolvency
- **Utilization Curve**: How interest rates automatically balance supply & demand
- **Liquidation**: How the protocol stays solvent when positions go bad
- **Interest Accrual**: Per-second interest calculation for millions of users

### ⚡ Implementation Phases

| Phase | Duration | What You'll Build |
|-------|----------|-------------------|
| 1 | Days 1-3 | Token contracts (AToken, DebtTokens) |
| 2 | Days 4-5 | Core lending (deposit, withdraw, borrow, repay) |
| 3 | Days 6-7 | Risk management (health factor, liquidations) |
| 4 | Week 2 | Interest accrual & rate strategies |
| 5 | Week 3 | Testing & security audit |
| 6 | Week 4+ | Advanced features (flash loans, isolation mode, etc.) |

### 🎓 Learning Style

**This project is designed for learning by doing:**
- You'll write every function from scratch
- Comments explain WHAT and WHY, not HOW
- Tests validate your understanding
- Security considerations highlighted

**No copy-paste allowed!**

### 📋 Pre-Implementation Checklist

- [ ] Read `docs/START_HERE.md`
- [ ] Read `docs/QUICK_REFERENCE.md`
- [ ] Understand what liquidityIndex is
- [ ] Know how health factor is calculated
- [ ] Understand utilization rate concept
- [ ] Ready to implement AToken.sol

### ✅ Success Criteria

**Week 1 Complete When:**
- All token contracts implemented & tested
- You understand how liquidityIndex works
- Tests pass: `forge test -vv`

**Week 2 Complete When:**
- Deposit/withdraw/borrow/repay working
- Health factor calculation accurate
- Liquidations functional
- Tests passing

**Project Complete When:**
- All features implemented
- 100+ test cases passing
- Security audit passed
- Ready for testnet deployment

### 🔗 Resources

- [AAVE V3 Documentation](https://docs.aave.com)
- [Compound Protocol](https://compound.finance)
- [OpenZeppelin Docs](https://docs.openzeppelin.com)
- [Solidity Docs](https://docs.soliditylang.org)

### 📞 Getting Help

When stuck:
1. Check `QUICK_REFERENCE.md` for common pitfalls
2. Read the TODO comments in the contract
3. Look at `DEVELOPMENT_ROADMAP.md` for that phase
4. Add `console.log()` and run tests with `-vv` flag

### ⚠️ Important Reminders

✅ DO:
- Understand before coding
- Test after each function
- Check the TODO comments
- Emit events for indexing
- Validate all inputs

❌ DON'T:
- Copy from other projects
- Skip understanding the math
- Forget health factor checks
- Transfer before state update
- Ignore test failures

---

**Ready to build? Open [docs/START_HERE.md](docs/START_HERE.md) now!** 🚀

---

## Foundry Documentation

```shell
$ forge fmt
```

### Gas Snapshots

```shell
$ forge snapshot
```

### Anvil

```shell
$ anvil
```

### Deploy

```shell
$ forge script script/Counter.s.sol:CounterScript --rpc-url <your_rpc_url> --private-key <your_private_key>
```

### Cast

```shell
$ cast <subcommand>
```

### Help

```shell
$ forge --help
$ anvil --help
$ cast --help
```
