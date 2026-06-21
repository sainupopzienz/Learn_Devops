#FROM nginx:alpine
#newline after trivy detects
FROM nginx:1.27-alpine
# newline after trivy detects Install latest security patches
RUN apk update && apk upgrade --no-cache
RUN rm -rf /usr/share/nginx/html/*
COPY index.html /usr/share/nginx/html/index.html
COPY topics/ /usr/share/nginx/html/topics/
RUN printf 'server {\n\
  listen 80;\n\
  root /usr/share/nginx/html;\n\
  index index.html;\n\
  location / {\n\
    try_files $uri $uri/ /index.html;\n\
    add_header Cache-Control "no-cache";\n\
  }\n\
  gzip on;\n\
  gzip_types text/html text/plain text/markdown application/javascript;\n\
}\n' > /etc/nginx/conf.d/default.conf
EXPOSE 80
CMD ["nginx", "-g", "daemon off;"]



