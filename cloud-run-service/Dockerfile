FROM node:20-alpine

# Install LibreOffice and fonts cleanly via Alpine APK
RUN apk add --no-cache \
    libreoffice \
    font-dejavu \
    ttf-liberation

WORKDIR /app

COPY package*.json ./
RUN npm install --production

COPY server.js ./

EXPOSE 8080

CMD ["npm", "start"]
