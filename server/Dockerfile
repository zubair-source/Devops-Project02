FROM node:13-alpine
RUN mkdir -p /home/app
RUN npm install
COPY . /home/app
EXPOSE 5000
CMD ["npm", "run", "start"]