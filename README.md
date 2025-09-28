# Kipu-Bank

## Descripción
**BancoKipu.sol** es un contrato inteligente que implementa un banco simple en Ethereum.  
Cada usuario tiene una bóveda personal de ETH donde puede **depositar** y **retirar** fondos, con límites configurados en el despliegue.  

## Características
- **Bóvedas personales**: cada dirección tiene saldo, depósitos y retiros registrados.  
- **Límites configurables**: 
  - `i_topeBanco` = máximo global de fondos.  
  - `i_topeRetiro` = máximo por retiro.  
- **Depósitos**: con `Depositar()` o enviando ETH directo (función `receive`).  
- **Retiros**: con `Retirar(uint256 monto)`, respetando saldo y límites.  
- **Eventos**: `Depositado` y `Retirado`.  
- **Funciones de consulta**: `ObtenerBoveda`, `Limites`, `Totales`.  

## Despliegue
1. Abrir [Remix](https://remix.ethereum.org/) y crear `contracts/BancoKipu.sol`.  
2. Compilar con Solidity `0.8.30`, licencia MIT.  
3. Conectar MetaMask a una testnet (Sepolia, Holesky, Goerli).  
4. Deploy → ingresar parámetros del constructor:  
   - `_topeBanco` (ej. `10 ether`).  
   - `_topeRetiro` (ej. `1 ether`).  
5. Confirmar transacción en MetaMask y guardar la dirección del contrato.  

## Verificación
En el explorador de bloques (ej. Sepolia Etherscan) usar **Verify & Publish**:  
- Versión de compilador `0.8.30`.  
- Licencia `MIT`.  
- Pegar el código fuente.  

## Interacción
- **Depositar ETH** → `Depositar()` con `value`.  
- **Retirar ETH** → `Retirar(monto)` en wei.  
- **Consultar** →  
  - `ObtenerBoveda(address)`  
  - `Limites()`  
  - `Totales()`  


