ssh server "cd /services && docker compose stop"
rsync -avz --delete --exclude 'media' server:/services/ /mnt/d/CodingConfigsDokus/Server/configs/
ssh server "cd /services && docker compose start"
