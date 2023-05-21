FROM node:14-alpine
WORKDIR /app
COPY package*.json ./
RUN npm i -force
COPY . .
EXPOSE 5000
CMD ["npm", "run", "start"]