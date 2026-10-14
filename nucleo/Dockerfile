FROM node:20-alpine
WORKDIR /app

# Contexto de build = raíz del repo: se copia comun/ junto al servicio.
COPY comun/package.json comun/package-lock.json ./comun/
RUN cd comun && npm ci --omit=dev
COPY nucleo/package.json nucleo/package-lock.json ./nucleo/
RUN cd nucleo && npm ci --omit=dev

COPY comun ./comun
COPY config ./config
COPY nucleo ./nucleo

WORKDIR /app/nucleo
ENV NODE_ENV=production
USER node
EXPOSE 3000
HEALTHCHECK --interval=5s --timeout=3s --start-period=5s --retries=10 \
  CMD wget -qO- http://127.0.0.1:3000/api/salud || exit 1
CMD ["node", "src/app.js"]
