# Imagen única para los seis microservicios (UT5). Cada servicio es un contenedor distinto:
# docker compose la construye una vez por servicio con --build-arg SERVICIO=<nombre>.
FROM node:20-alpine
ARG SERVICIO
ENV SERVICIO=${SERVICIO}
WORKDIR /app

# Contexto de build = raíz del repo: se copia comun/ junto al servicio.
COPY comun/package.json comun/package-lock.json ./comun/
RUN cd comun && npm ci --omit=dev
COPY ${SERVICIO}/package.json ${SERVICIO}/package-lock.json ./${SERVICIO}/
RUN cd ${SERVICIO} && npm ci --omit=dev

COPY comun ./comun
COPY config ./config
COPY ${SERVICIO} ./${SERVICIO}

WORKDIR /app/${SERVICIO}
ENV NODE_ENV=production
USER node
EXPOSE 3000
# Readiness del servicio: si su base no responde (o se inyecta una falla) el contenedor queda unhealthy.
HEALTHCHECK --interval=5s --timeout=3s --start-period=15s --retries=3 \
  CMD wget -qO- "http://127.0.0.1:3000/api/salud/${SERVICIO}/listo" || exit 1
CMD ["node", "src/app.js"]
