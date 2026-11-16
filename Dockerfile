# The computer players' server (bot_server/). Build from the repository
# root, because it shares the app's reasoning code in lib/:
#   docker build -t avalon-bots .
# The same image runs on Cloud Run and (built on the Pi, or with
# --platform linux/arm64) on a Raspberry Pi.
FROM dart:stable AS build
WORKDIR /app
COPY bot_server/pubspec.yaml bot_server/
RUN cd bot_server && dart pub get
COPY lib lib
COPY bot_server bot_server
RUN dart compile exe bot_server/bin/server.dart -o /app/server

FROM scratch
COPY --from=build /runtime/ /
COPY --from=build /app/server /app/server
EXPOSE 8080
CMD ["/app/server"]
