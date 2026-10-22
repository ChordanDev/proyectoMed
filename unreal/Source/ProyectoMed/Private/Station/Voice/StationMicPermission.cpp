#include "Station/StationMicPermission.h"

#include "Async/Async.h"

#if PLATFORM_MAC
#include "Mac/MacSystemIncludes.h"
#include "Apple/PreAppleSystemHeaders.h"
#include <AVFoundation/AVFoundation.h>
#include "Apple/PostAppleSystemHeaders.h"
#endif

EStationMicPermission StationMicPermission::Get()
{
#if PLATFORM_MAC
	switch ([AVCaptureDevice authorizationStatusForMediaType:AVMediaTypeAudio])
	{
	case AVAuthorizationStatusAuthorized:
		return EStationMicPermission::Granted;
	case AVAuthorizationStatusNotDetermined:
		return EStationMicPermission::NotDetermined;
	default:
		return EStationMicPermission::Denied;
	}
#else
	return EStationMicPermission::Granted;
#endif
}

void StationMicPermission::Request(TFunction<void(EStationMicPermission)> OnDone)
{
#if PLATFORM_MAC
	if (Get() == EStationMicPermission::NotDetermined)
	{
		TFunction<void(EStationMicPermission)>* Callback = new TFunction<void(EStationMicPermission)>(MoveTemp(OnDone));
		[AVCaptureDevice requestAccessForMediaType:AVMediaTypeAudio completionHandler:^(BOOL bGranted)
		{
			AsyncTask(ENamedThreads::GameThread, [Callback, bGranted]()
			{
				(*Callback)(bGranted ? EStationMicPermission::Granted : EStationMicPermission::Denied);
				delete Callback;
			});
		}];
		return;
	}
#endif
	OnDone(Get());
}
