// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

/**
 * @title BancoKipu
 * @notice Contrato que implementa un banco simple en Ethereum, donde cada usuario tiene una bóveda personal de ETH. 
 *         Permite depósitos y retiros con restricciones configuradas en el despliegue.
 *
 * @dev 
 * - Cada usuario se gestiona mediante un mapping `s_bovedas[address]` que almacena: su saldo, la cantidad de depósitos y retiros realizados.
 * - Existen límites inmutables definidos en el constructor:
 *      {i_topeBanco} → límite global de fondos que puede custodiar el contrato.
 *      {i_topeRetiro} → límite máximo de retiro permitido por transacción.
 * - El contrato implementa funciones `receive` y `fallback` para manejar ETH enviado directamente.
 * - Se utilizan modificadores para validar condiciones comunes (saldo no cero, límites, etc.), siguiendo buenas prácticas de legibilidad y seguridad.
 * - Incluye el patrón checks-effects-interactions y errores personalizados para un mejor manejo de revert.
 *
 */
contract BancoKipu {


/*//////////////////////////////////////////////////////////////
                        Declaraciones de tipo
//////////////////////////////////////////////////////////////*/
    /**
    * @notice Datos de la bóveda individual de un usuario.
    * @dev Se almacena en el mapping `s_bovedas[usuario]`.
    */
    struct Boveda {
       /**
       * @notice Saldo actual de la bóveda en wei.
       * @dev `uint256` alinea con el tipo nativo de ETH y evita conversiones.
       */
       uint256 saldo;
        /**
        * @notice Cantidad de depósitos realizados por el usuario.
        * @dev `uint32` para contador no negativo y ahorrar gas.
        */
        uint32 depositos;
        /**
        * @notice Cantidad de retiros efectuados por el usuario.
        * @dev `uint32` para contador no negativo y ahorrar gas.
        */
        uint32 retiros;
    }


/*//////////////////////////////////////////////////////////////
                         Variables de estado
//////////////////////////////////////////////////////////////*/

    // Inmutables

    /**
    * @notice Tope global de fondos (en wei) que el banco puede custodiar en todas las bóvedas.
    * @dev Inmutable: se define al desplegar el contrato y no puede modificarse después.
    */
    uint256 public immutable i_topeBanco;

    /**
    * @notice Tope máximo permitido por transacción de retiro (en wei).
    * @dev Inmutable: se establece en el constructor y permanece fijo.
    */
    uint256 public immutable i_topeRetiro;

    // Estado

    /**
    * @notice Bóvedas de los usuarios, indexadas por dirección.
    * @dev Cada dirección apunta a una struct {Boveda} con saldo (en wei), depósitos y retiros.
    */
    mapping(address => Boveda) private s_bovedas;

    /**
    * @notice Suma global de todos los saldos de las bóvedas (en wei).
    * @dev Se actualiza en cada operación de depósito y retiro.
    *      Sirve para validar que no se supere el {i_topeBanco}.
    */
    uint256 private s_totalFondos;

    /**
    * @notice Cantidad total de depósitos realizados por todos los usuarios.
    * @dev Contador global. Útil para métricas y auditoría. (no es un monto en wei).
    */
    uint256 private s_totalDepositos;

    /**
    * @notice Cantidad total de retiros realizados por todos los usuarios.
    * @dev Contador global. Útil para métricas y auditoría. (no es un monto en wei).
    */
    uint256 private s_totalRetiros;


/*//////////////////////////////////////////////////////////////
                              Eventos
//////////////////////////////////////////////////////////////*/
    
    /**
    * @notice Emite cuando un usuario deposita fondos en su bóveda.
    * @param usuario Dirección del depositante.
    * @param monto   Cantidad de ETH depositada (en wei).
    * @param nuevoSaldo Saldo actualizado de la bóveda después del depósito (en wei).
    * @dev El parámetro {usuario} está marcado como `indexed` para facilitar la búsqueda de todos los depósitos de una dirección en los logs de la blockchain.
    */
    event Depositado(address indexed usuario, uint256 monto, uint256 nuevoSaldo);
    

    /**
    * @notice Emite cuando un usuario retira fondos de su bóveda.
    * @param usuario Dirección del retirante.
    * @param monto   Cantidad de ETH retirada (en wei).
    * @param nuevoSaldo Saldo actualizado de la bóveda después del retiro (en wei).
    * @dev El parámetro {usuario} está marcado como `indexed` para permitir filtrar rápidamente los retiros de una dirección en exploradores o en los logs de la blockchain.
    */ 
    event Retirado(address indexed usuario, uint256 monto, uint256 nuevoSaldo);


/*//////////////////////////////////////////////////////////////
                              Errores
//////////////////////////////////////////////////////////////*/
    
    
    /**
    * @notice Error lanzado cuando se intenta realizar un retiro con monto cero.
    */
    error BancoKipu_RetiroCero();
    
    /**
    * @notice Error lanzado cuando se intenta realizar un depósito con monto cero.
    */
    error BancoKipu_DepositoCero();
    
    /**
    * @notice Error lanzado cuando la suma global de fondos supera el tope del banco.
    * @param nuevoTotal Valor total (en wei) que se intentó registrar.
    * @param topeBanco  Límite máximo permitido (en wei).
    */
    error BancoKipu_TopeBancoExcedido(uint256 nuevoTotal, uint256 topeBanco);
    
    /**
    * @notice Error lanzado cuando un retiro excede el tope por transacción.
    * @param solicitado Monto solicitado por el usuario (en wei).
    * @param maximoPorTx Límite máximo de retiro permitido por transacción (en wei).
    */
    error BancoKipu_RetiroSobreTope(uint256 solicitado, uint256 maximoPorTx);
    
    /**
    * @notice Error lanzado cuando un usuario intenta retirar más de lo que posee.
    * @param saldo     Saldo disponible en la bóveda (en wei).
    * @param solicitado Monto solicitado para retiro (en wei).
    */
    error BancoKipu_SaldoInsuficiente(uint256 saldo, uint256 solicitado);
    
    /**
    * @notice Error lanzado cuando falla la transferencia nativa de ETH mediante `call`.
    * @param errorBajoNivel Datos de error devueltos por la llamada de bajo nivel.
    */
    error BancoKipu_TransferenciaNativaFallida(bytes errorBajoNivel);


/*//////////////////////////////////////////////////////////////
                           Modificadores
//////////////////////////////////////////////////////////////*/
    
    /**
    * @notice Verifica que el monto a retirar no sea cero.
    * @param _monto Cantidad en wei que se está validando.
    */
    modifier retiroNoCero(uint256 _monto) {
        if (_monto == 0) revert BancoKipu_RetiroCero();
        _;
    }

    /**
    * @notice Verifica que el monto no supere el tope de retiro configurado.
    * @param _monto Cantidad en wei a retirar.
    */
    modifier bajoTopeRetiro(uint256 _monto) {
        if (_monto > i_topeRetiro) revert BancoKipu_RetiroSobreTope(_monto, i_topeRetiro);
        _;
    }

    /**
    * @notice Verifica que el usuario tenga saldo suficiente para realizar la operación.
    * @param _monto Cantidad en wei que se quiere retirar.
    */
    modifier saldoSuficiente(uint256 _monto) {
        uint256 _saldo = s_bovedas[msg.sender].saldo;
        if (_saldo < _monto) revert BancoKipu_SaldoInsuficiente(_saldo, _monto);
        _;
    }

    /**
    * @notice Verifica que el depósito no sea cero.
    * @param _valor Cantidad en wei que se intenta depositar.
    */
    modifier depositoNoCero(uint256 _valor) {
        if (_valor == 0) revert BancoKipu_DepositoCero();
        _;
    }

    /**
    * @notice Verifica que la suma de fondos global no supere el tope del banco.
    * @param _valor Cantidad en wei que se intenta añadir al total.
    */
    modifier bajoTopeBanco(uint256 _valor) {
        uint256 _nuevoTotal = s_totalFondos + _valor;
        if (_nuevoTotal > i_topeBanco) revert BancoKipu_TopeBancoExcedido(_nuevoTotal, i_topeBanco);
        _;
    }


/*//////////////////////////////////////////////////////////////
                             Constructor
//////////////////////////////////////////////////////////////*/

    /**
     * @notice Inicializa el contrato con los límites principales del banco.
     * @dev Ambos parámetros se asignan a variables inmutables (`immutable`), lo que significa que no pueden modificarse después del despliegue.
     *      Las reglas de capacidad son fijas y conocidas desde el inicio.
     *
     * @param _topeBanco   Tope global de fondos (en wei) que el banco puede custodiar entre todas las bóvedas de usuarios.
     * @param _topeRetiro  Tope máximo de ETH (en wei) que un usuario puede retirar en una sola transacción.
     */
    constructor(uint256 _topeBanco, uint256 _topeRetiro) {
        i_topeBanco  = _topeBanco;
        i_topeRetiro = _topeRetiro;
    }

/*//////////////////////////////////////////////////////////////
                         Receive y Fallback
//////////////////////////////////////////////////////////////*/
    
    /**
     * @notice Función especial que se ejecuta automáticamente cuando el contrato recibe ETH sin ningún dato (`data` vacío).
     * @dev Redirige el monto recibido a la función interna {_depositar}, de modo que siempre se contabilice como un depósito en la bóveda personal del remitente (`msg.sender`).
     *      - Permite que los usuarios envíen ETH directamente al contrato sin necesidad de llamar a `Depositar()`.
     */
    receive() external payable {
        _depositar(msg.sender, msg.value);
    }

    /**
     * @notice Función especial de último recurso que se ejecuta cuando se llama al contrato con datos que no coinciden con ninguna función existente.
     * @dev Esta implementación:
     *      - No es `payable`, por lo que cualquier intento de enviar ETH mediante `fallback` será rechazado (revierte).
     *      - Si solo se invoca con datos inválidos pero sin ETH, la transacción no hace nada y no revierte.
     *      Se deja definida explícitamente para tener un comportamiento claro y seguro en caso de llamadas incorrectas.
     */
    fallback() external {}

/*//////////////////////////////////////////////////////////////
                              External
//////////////////////////////////////////////////////////////*/

    /**
     * @notice Deposita ETH en la bóveda personal del remitente.
     * @dev Internamente delega la lógica a {_depositar}.
     */
    function Depositar() external payable {
        _depositar(msg.sender, msg.value);
    }

    /**
     * @notice Retira fondos de la bóveda personal del remitente, respetando el límite máximo por transacción.
     * @param _monto Cantidad en wei a retirar.
     * @dev 
     * - Aplica varios modificadores antes de ejecutar la lógica:
     *    {retiroNoCero} → asegura que no se intente retirar 0.
     *    {bajoTopeRetiro} → valida que el retiro no exceda {i_topeRetiro}.
     *    {saldoSuficiente} → comprueba que el usuario tenga fondos suficientes para el retiro.
     *
     * - Sigue el patrón *checks-effects-interactions*:
     *    1. Checks: se validan las condiciones vía modificadores.
     *    2. Effects: se actualizan los saldos en storage
     *         (`b.saldo`, `s_totalFondos`, contadores de retiros).
     *    3. Interactions: se transfiere el ETH al usuario con {_transferirEth}.
     *
     * - Emite el evento {Retirado} para dejar un registro en la blockchain.
     */
    function Retirar(uint256 _monto)
        external
        retiroNoCero(_monto)
        bajoTopeRetiro(_monto)
        saldoSuficiente(_monto)
    {
        // effects
        Boveda storage b = s_bovedas[msg.sender];
        uint256 _saldo = b.saldo;
        
        b.saldo = _saldo - _monto; //Actualiza saldo cuenta en map
        b.retiros += 1; //Actualiza total de retiros del usuario
        s_totalFondos -= _monto; //Actualiza total de fondos del banco
        s_totalRetiros += 1; //Actualiza total de retiros del banco

        // interactions
        _transferirEth(payable(msg.sender), _monto);

        emit Retirado(msg.sender, _monto, b.saldo);
    }

/*//////////////////////////////////////////////////////////////
                              Private
//////////////////////////////////////////////////////////////*/
    /**
    * @dev Lógica común de depósito usada por {Depositar} y {receive}.
    *   Reglas aplicadas por modificadores:
    *   - {depositoNoCero}: asegura que el monto que se intenta depositar no sea 0.
    *   - {bajoTopeBanco}: valida que el nuevo total de fondos no supere {i_topeBanco}.
    *
    *   Efectos:
    *   - Incrementa el saldo de la bóveda del usuario.
    *   - Aumenta los contadores de depósitos del usuario y global.
    *   - Ajusta el total de fondos custodiados.
    *
    *   Eventos:
    *   - Emite {Depositado} con la dirección, monto y nuevo saldo del usuario.
    * @param _desde Dirección del usuario que envía los fondos.
    * @param _valor Monto depositado (en wei).
    */
    function _depositar(address _desde, uint256 _valor)
        private
        depositoNoCero(_valor)
        bajoTopeBanco(_valor)
    {
        Boveda storage b = s_bovedas[_desde];
        b.saldo      += _valor;
        b.depositos  += 1;
        s_totalDepositos  += 1;
        s_totalFondos     += _valor;

        emit Depositado(_desde, _valor, b.saldo);
    }

    /**
    * @dev Envía ETH al destinatario usando `.call`.
    *   Detalles técnicos:
    *   - `.call{value: _valor}("")` se utiliza en lugar de `.transfer` o `.send` porque:
    *       1) Evita el límite fijo de gas (2300) impuesto por `.transfer`.
    *       2) Permite manejar contratos receptores con lógica compleja.
    *   - Si la llamada falla, se captura el error de bajo nivel y se revierte con el error personalizado {BancoKipu_TransferenciaNativaFallida}.
    *
    *   Seguridad:
    *   - Sigue el patrón checks-effects-interactions, ya que esta función solo se llama después de actualizar el estado.
    *   - Sigue principio de modularidad de funciones.
    * @param _destino Dirección del receptor (payable).
    * @param _valor   Cantidad a transferir (en wei).
    */
    function _transferirEth(address payable _destino, uint256 _valor) private {
        (bool _ok, bytes memory _err) = _destino.call{value: _valor}("");
        if (!_ok) revert BancoKipu_TransferenciaNativaFallida(_err);
    }

/*//////////////////////////////////////////////////////////////
                           View y Pure
//////////////////////////////////////////////////////////////*/
    
    /**
     * @notice Devuelve la información detallada de la bóveda de un usuario.
     * @param _usuario Dirección del usuario cuya bóveda se consulta.
     * @return saldo_     Saldo actual de la bóveda (en wei).
     * @return depositos_ Número total de depósitos realizados por el usuario.
     * @return retiros_   Número total de retiros efectuados por el usuario.
     */
    function ObtenerBoveda(address _usuario)
        external
        view
        returns (uint256 saldo_, uint32 depositos_, uint32 retiros_)
    {
        Boveda storage b = s_bovedas[_usuario];
        saldo_     = b.saldo;
        depositos_ = b.depositos;
        retiros_   = b.retiros;
    }

    
    /**
     * @notice Devuelve los límites configurados en el contrato.
     * @return topeBanco_  Límite global de fondos que el banco puede custodiar (en wei).
     * @return topeRetiro_ Límite máximo permitido por transacción de retiro (en wei).
     */
    function Limites()
        external
        view
        returns (uint256 topeBanco_, uint256 topeRetiro_)
    {
        topeBanco_  = i_topeBanco;
        topeRetiro_ = i_topeRetiro;
    }

    /**
     * @notice Devuelve las métricas globales del banco.
     * @return totalFondos_    Suma de todos los saldos de las bóvedas (en wei).
     * @return totalDepositos_ Cantidad de depósitos realizados por todos los usuarios (contador).
     * @return totalRetiros_   Cantidad de retiros realizados por todos los usuarios (contador).
     */
    function Totales()
        external
        view
        returns (uint256 totalFondos_, uint256 totalDepositos_, uint256 totalRetiros_)
    {
        totalFondos_    = s_totalFondos;
        totalDepositos_ = s_totalDepositos;
        totalRetiros_   = s_totalRetiros;
    }
}
