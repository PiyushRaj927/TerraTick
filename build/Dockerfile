FROM nikolaik/python-nodejs:python3.10-nodejs20
RUN apt update && apt install -y zip
COPY --chmod=0755 ./entrypoint.sh /
ENTRYPOINT [ "/entrypoint.sh" ]

