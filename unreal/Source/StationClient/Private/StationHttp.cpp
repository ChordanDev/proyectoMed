#include "StationHttp.h"

#include "Dom/JsonObject.h"
#include "HttpModule.h"
#include "Interfaces/IHttpRequest.h"
#include "Interfaces/IHttpResponse.h"
#include "Serialization/JsonReader.h"
#include "Serialization/JsonSerializer.h"
#include "Serialization/JsonWriter.h"
#include "StationClientLog.h"

namespace
{
	TSharedPtr<FJsonObject> ParseBody(const FString& Body)
	{
		TSharedPtr<FJsonObject> Object;
		FJsonSerializer::Deserialize(TJsonReaderFactory<>::Create(Body), Object);
		return Object;
	}

	FStationHttpResponse ToResponse(const FHttpResponsePtr& HttpResponse, bool bConnected, const FString& Url)
	{
		FStationHttpResponse Response;
		if (!bConnected || !HttpResponse.IsValid())
		{
			Response.Error = StationHttp::ClientError(TEXT("network_error"),
				FString::Printf(TEXT("Phoenix did not answer at %s."), *Url));
			return Response;
		}

		Response.Status = HttpResponse->GetResponseCode();
		const FString Body = HttpResponse->GetContentAsString();
		const TSharedPtr<FJsonObject> Json = Body.IsEmpty() ? nullptr : ParseBody(Body);

		if (EHttpResponseCodes::IsOk(Response.Status))
		{
			if (!Body.IsEmpty() && !Json.IsValid())
			{
				Response.Error = FStationClientError{Response.Status, TEXT("invalid_response"),
					TEXT("Phoenix answered with a body that is not a JSON object.")};
			}
			Response.Json = Json;
			return Response;
		}

		FStationClientError Error{Response.Status, FString::Printf(TEXT("http_%d"), Response.Status), FString()};
		if (Json.IsValid())
		{
			Json->TryGetStringField(TEXT("error"), Error.Code);
			Json->TryGetStringField(TEXT("message"), Error.Message);
		}
		Response.Error = MoveTemp(Error);
		return Response;
	}
}

void StationHttp::Send(const FString& Verb, const FString& Url, const TSharedPtr<FJsonObject>& Body,
	TFunction<void(const FStationHttpResponse&)> OnDone)
{
	const TSharedRef<IHttpRequest, ESPMode::ThreadSafe> Request = FHttpModule::Get().CreateRequest();
	Request->SetVerb(Verb);
	Request->SetURL(Url);
	Request->SetHeader(TEXT("Accept"), TEXT("application/json"));
	Request->SetTimeout(RequestTimeoutSeconds);

	if (Body.IsValid())
	{
		FString Payload;
		FJsonSerializer::Serialize(Body.ToSharedRef(), TJsonWriterFactory<>::Create(&Payload));
		Request->SetHeader(TEXT("Content-Type"), TEXT("application/json"));
		Request->SetContentAsString(Payload);
	}

	Request->OnProcessRequestComplete().BindLambda(
		[OnDone = MoveTemp(OnDone), Verb, Url](FHttpRequestPtr, FHttpResponsePtr HttpResponse, bool bConnected)
		{
			const FStationHttpResponse Response = ToResponse(HttpResponse, bConnected, Url);
			if (Response.Error.IsSet())
			{
				UE_LOG(LogStationClient, Warning, TEXT("%s %s failed: %d %s"),
					*Verb, *Url, Response.Error->HttpStatus, *Response.Error->Code);
			}
			OnDone(Response);
		});

	Request->ProcessRequest();
}

FStationClientError StationHttp::ClientError(const FString& Code, const FString& Message)
{
	return FStationClientError{0, Code, Message};
}
