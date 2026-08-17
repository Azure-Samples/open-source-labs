# go-azure-service-bus-receiver

Command notes

```bash
# download dependencies from the existing module
go mod download

# set some environment variables
export AZURE_SERVICEBUS_CONNECTION_STRING="Endpoint=sb://<YOUR_NAMESPACE>.servicebus.windows.net/;SharedAccessKeyName=RootManageSharedAccessKey;SharedAccessKey=<YOUR_SHARED_ACCESS_KEY>"
export AZURE_SERVICEBUS_QUEUE_NAME="myqueue"
export BATCH_SIZE=2

# run the app locally
go run main.go

# build the docker container
docker build -t go-azure-service-bus-receiver:v0.0.1 .

# run the docker container
docker run -e AZURE_SERVICEBUS_CONNECTION_STRING="Endpoint=sb://<YOUR_NAMESPACE>.servicebus.windows.net/;SharedAccessKeyName=RootManageSharedAccessKey;SharedAccessKey=<YOUR_SHARED_ACCESS_KEY>" -e AZURE_SERVICEBUS_QUEUE_NAME=myqueue -e BATCH_SIZE=10 go-azure-service-bus-receiver:v0.0.1
```
