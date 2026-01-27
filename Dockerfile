# Build Go server
FROM golang:1.22-alpine AS server-build
WORKDIR /src
COPY server/go.mod server/go.sum* ./server/
WORKDIR /src/server
RUN go mod download
COPY server .
RUN CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build -o /out/tic-tac-toe-server .

# Runtime
FROM alpine:3.20
WORKDIR /app
COPY --from=server-build /out/tic-tac-toe-server /app/tic-tac-toe-server
COPY build/web /app/web
ENV ADDR=:8080
ENV WEB_DIR=/app/web
EXPOSE 8080
ENTRYPOINT ["/app/tic-tac-toe-server"]
