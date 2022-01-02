truffle compile
truffle migrate --reset --network testnet --compile-none --migrations './migrations/tokens'
truffle run verify BTS BTD BTB --network testnet
truffle migrate --reset --network testnet --compile-none --migrations  './migrations/bank'
truffle run verify LPTokenBank Zapper --network testnet
truffle migrate --reset --network testnet --compile-none --migrations  './migrations/migrator'
truffle migrate --reset --network testnet --compile-none --migrations  './migrations/treasury'
truffle run verify Treasury DollarOracle SingleTokenBoardroom LPTokenBoardroom BoardroomAllocation  --network testnet
truffle migrate --reset --network testnet --compile-none --migrations  './migrations/dollarswap'
truffle run verify DollarSwap --network testnet
truffle exec ./scripts/assignDeveloperRoles.js --network testnet