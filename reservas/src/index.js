// Interfaz pública del componente Reservas.
const servicio = require('./servicio');

module.exports = {
  // Interfaz: ReservarClase (HU5, HU6)
  reservarClase: servicio.reservarClase,
  // Interfaz: ConfirmarClaseDictada (HU11)
  confirmarClaseDictada: servicio.confirmarClaseDictada,
  listarReservas: servicio.listarReservas,
  obtenerReserva: servicio.obtenerReserva,
  horariosOcupados: servicio.horariosOcupados,
  router: require('./rutas'),
};
