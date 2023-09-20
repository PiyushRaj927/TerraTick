FROM python:3.10.13-slim
RUN pip install zappa flask
COPY --chmod=0755 ./entrypoint.sh /
ENTRYPOINT [ "/entrypoint.sh" ]

