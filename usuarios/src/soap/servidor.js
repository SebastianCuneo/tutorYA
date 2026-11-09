// Servidor SOAP de Usuarios (UT5): expone ConsultarEstadoEstudiante con el contrato estudiantes.wsdl.
// GET /soap/estudiantes?wsdl devuelve el contrato; POST /soap/estudiantes recibe el sobre SOAP (XML).
// La lógica es la misma que tenía el endpoint REST: solo cambia el protocolo y el formato.
const fs = require('fs');
const express = require('express');
const path = require('path');
const { soap, logger } = require('../../../comun');
const servicio = require('../servicio');

const RUTA = '/soap/estudiantes';
const wsdl = fs.readFileSync(path.join(__dirname, 'estudiantes.wsdl'), 'utf8');

// Error de negocio -> SOAP Fault (soap:Client si el pedido es inválido o no existe; soap:Server si no).
function fault(e) {
  const cliente = e.status && e.status < 500;
  return {
    Fault: {
      faultcode: cliente ? 'soap:Client' : 'soap:Server',
      faultstring: e.message,
      detail: { codigo: e.codigo || 'ERROR_INTERNO' },
      statusCode: cliente ? 400 : 500,
    },
  };
}

const implementacion = {
  EstudiantesService: {
    EstudiantesPort: {
      async ConsultarEstadoEstudiante(args) {
        const id = Number(args.estudianteId);
        try {
          if (!Number.isInteger(id)) throw Object.assign(new Error('estudianteId inválido'), { status: 400, codigo: 'VALIDACION' });
          return await servicio.consultarEstadoEstudiante(id);
        } catch (e) {
          throw fault(e);
        }
      },
    },
  },
};

// Se monta en un Router propio, agregado a la app antes del 404: node-soap registra la ruta recién
// cuando terminó de leer el WSDL (asíncrono), así que no puede ir directo sobre la app.
function montar(app) {
  const router = express.Router();
  app.use(router);
  const servidor = soap.listen(router, RUTA, implementacion, wsdl);
  servidor.log = (tipo, datos) => {
    if (tipo === 'error') logger.warn('soap: error', { datos: String(datos).slice(0, 300) });
  };
  logger.info(`SOAP publicado en ${RUTA} (WSDL en ${RUTA}?wsdl)`);
}

module.exports = { montar, RUTA };
