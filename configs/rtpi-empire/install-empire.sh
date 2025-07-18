# with persistent storage
cd /opt/
git clone --recursive https://github.com/BC-SECURITY/Empire.git
cd Empire/
./setup/checkout-latest-tag.sh
./ps-empire install -f -y 

./ps-empire server