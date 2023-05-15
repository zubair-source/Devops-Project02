FROM node:14.16.1-alpine3.13
WORKDIR /api
COPY server/package*.json ./
RUN npm install
COPY server ./
ENV NAME=subin
EXPOSE 5000
CMD ["npm","start"]