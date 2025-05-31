FROM node:18-alpine

# 安装 Chromium 和依赖
RUN apk add --no-cache \
    chromium \
    nss \
    ca-certificates

# 设置 Puppeteer 环境变量
ENV PUPPETEER_SKIP_CHROMIUM_DOWNLOAD=true
ENV PUPPETEER_EXECUTABLE_PATH=/usr/bin/chromium-browser

WORKDIR /app

COPY package*.json ./
RUN npm install --only=production

COPY . .

EXPOSE 8080

CMD ["npm", "start"] 