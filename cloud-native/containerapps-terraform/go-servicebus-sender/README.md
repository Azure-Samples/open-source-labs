# go-azure-service-bus-sender

This codebase is inspired by the following docs:

- [Send messages to and receive messages from Azure Service Bus queues (Go)](https://learn.microsoft.com/azure/service-bus-messaging/service-bus-go-how-to-use-queues?tabs=bash)
- [Sending multiple messages using a batch](https://pkg.go.dev/github.com/Azure/azure-sdk-for-go/sdk/messaging/azservicebus@v1.1.0#readme-sending-multiple-messages-using-a-batch)

To run this app locally, make sure you have ran the `terraform apply` command from the `./terraform` directory. Once all the Azure resources have been provisioned you can run the following:

```bash
export AZURE_SERVICEBUS_CONNECTION_STRING="Endpoint=sb://<YOUR_NAMESPACE>.servicebus.windows.net/;SharedAccessKeyName=RootManageSharedAccessKey;SharedAccessKey=<YOUR_SHARED_ACCESS_KEY>"
export AZURE_SERVICEBUS_QUEUE_NAME="myqueue"
export BATCH_SIZE=10
```
