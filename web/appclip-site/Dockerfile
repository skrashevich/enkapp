FROM nginx:1.27-alpine

RUN apk add --no-cache gettext

COPY nginx.conf /etc/nginx/conf.d/default.conf
COPY public /usr/share/nginx/html
COPY docker-entrypoint.d/40-render-enkapp-site.sh /docker-entrypoint.d/40-render-enkapp-site.sh

RUN chmod +x /docker-entrypoint.d/40-render-enkapp-site.sh
