CALL :NORMALIZEPATH "./migrations/config/bsc/testnet.json"
SET configPath=%RETVAL%
ECHO "%configPath%"

call truffle compile

call truffle migrate --reset --network testnet --compile-none --output %configPath% --migrations './migrations/tokens'
call truffle run verify Charge Static Pulse --network testnet

call truffle migrate --reset --network testnet --compile-none --output %configPath% --migrations './migrations/bank'
call truffle run verify LPTokenBank Zapper --network testnet

@REM not using migrator anymore
@REM call truffle migrate --reset --network testnet --compile-none --output %configPath% --migrations './migrations/migrator'

call truffle migrate --reset --network testnet --compile-none --output %configPath% --migrations './migrations/treasury'
call truffle run verify Treasury DollarOracle SingleTokenBoardroom LPTokenBoardroom BoardroomAllocation BoardroomStats --network testnet

call truffle migrate --reset --network testnet --compile-none --output %configPath% --migrations './migrations/dollarswap'
call truffle run verify DollarSwap --network testnet

call truffle migrate --reset --network testnet --compile-none --output %configPath% --migrations './migrations/presale'
call truffle run verify PreSale --network testnet

call truffle exec ./scripts/btdExclusions.js --network testnet
call truffle exec ./scripts/assignDeveloperRoles.js --network testnet


:: ========== FUNCTIONS ==========
EXIT /B

:NORMALIZEPATH
  SET RETVAL=%~f1
  EXIT /B