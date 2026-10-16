FROM node:22-alpine
WORKDIR /app
COPY server.js .
ENV NODE_ENV=production
USER node
EXPOSE 3000
CMD ["node", "server.js"]