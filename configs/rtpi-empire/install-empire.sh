# with persistent storage
docker pull bcsecurity/empire:latest
docker create -v /empire --name data bcsecurity/empire:latest
docker run -d -it -p 1337:1337 -p 5000:5000 --volumes-from data --name ps-empire bcsecurity/empire:latest