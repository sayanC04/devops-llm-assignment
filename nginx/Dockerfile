FROM nginx:alpine

# The official Nginx Alpine image automatically processes templates in /etc/nginx/templates/ 
# using envsubst and writes them to /etc/nginx/conf.d/ at container startup.
COPY default.conf.template /etc/nginx/templates/default.conf.template

# Default env fallback if needed
ENV CALLER_IP=127.0.0.1
