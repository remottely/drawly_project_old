package main

func emitClientError(client ClientConn, message string, action ErrorActionType) {
	client.Emit(EventError, ErrorDTO{
		Message: message,
		Action:  action,
	})
}
