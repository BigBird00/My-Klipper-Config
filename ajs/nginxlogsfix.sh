echo "recreating log files for nginx
sudo mkdir -p /var/log
sudo mkdir -p /var/log/nginx
sudo touch /var/log/nginx/access.log
sudo touch /var/log/nginx/error.log
sudo chown -R www-data:www-data /var/log/nginx
echo "Done Creating Logs and .log files"