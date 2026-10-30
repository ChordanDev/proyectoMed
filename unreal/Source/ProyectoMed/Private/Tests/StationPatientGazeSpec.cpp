// Patient gaze tests (#449). `ProyectoMed.PatientGaze.Unit` needs nothing else;
// `ProyectoMed.PatientGaze.Scene` loads the consultation's MetaHuman.

#include "Animation/AnimSequence.h"
#include "AnimationRuntime.h"
#include "Camera/CameraActor.h"
#include "Engine/SkeletalMesh.h"
#include "Components/SkeletalMeshComponent.h"
#include "Engine/Engine.h"
#include "Engine/World.h"
#include "Misc/AutomationTest.h"
#include "Station/Patient/StationGaze.h"
#include "Station/Patient/StationPatientGaze.h"
#include "Station/StationPlayerController.h"
#include "Station/StationRunFlow.h"
#include "Station/Voice/StationFaceBlend.h"
#include "Station/Voice/StationPatientFaceAnim.h"

#if WITH_DEV_AUTOMATION_TESTS

namespace
{
	constexpr float FrameSeconds = 1.f / 60.f;

	/** What a stretch of gaze did, frame by frame. */
	struct FGazeRun
	{
		/** How long each look at the learner and each glance away lasted, whole ones only. */
		TArray<float> ContactSeconds;
		TArray<float> AwaySeconds;
		/** The share of the time the eyes met the learner's view. */
		float EyeContactShare = 0.f;
		/** The longest unbroken eye contact. */
		float LongestEyeContact = 0.f;
		/** The largest change of the eyes and of the head in one frame. */
		float LargestEyeStep = 0.f;
		float LargestHeadStep = 0.f;
		/** The furthest the eyes and head turned, and the furthest a gaze strayed from the learner. */
		FStationGazeAngles EyeMin, EyeMax, HeadMin, HeadMax;
		float LargestStray = 0.f;
	};

	float Distance(const FStationGazeAngles& A, const FStationGazeAngles& B)
	{
		return FMath::Sqrt(FMath::Square(A.Yaw - B.Yaw) + FMath::Square(A.Pitch - B.Pitch));
	}

	FStationGazeAngles Sum(const FStationGazeAngles& A, const FStationGazeAngles& B)
	{
		return { A.Yaw + B.Yaw, A.Pitch + B.Pitch };
	}

	void Widen(FStationGazeAngles& Min, FStationGazeAngles& Max, const FStationGazeAngles& Value)
	{
		Min = { FMath::Min(Min.Yaw, Value.Yaw), FMath::Min(Min.Pitch, Value.Pitch) };
		Max = { FMath::Max(Max.Yaw, Value.Yaw), FMath::Max(Max.Pitch, Value.Pitch) };
	}

	/** Runs `Model` for `Seconds` in `Mode`, with the learner at `ToLearner`. */
	FGazeRun Run(FStationGazeModel& Model, EStationGazeMode Mode, float Seconds,
		FStationGazeAngles ToLearner = {}, float Step = FrameSeconds)
	{
		FGazeRun Out;
		EStationGazePhase Phase = Model.GetPhase();
		float PhaseTime = 0.f;
		bool bWholePhase = false;
		int32 ContactFrames = 0;
		int32 Frames = 0;
		float EyeContact = 0.f;
		for (float Time = 0.f; Time < Seconds; Time += Step)
		{
			const FStationGazeAngles Eyes = Model.GetEyes();
			const FStationGazeAngles Head = Model.GetHead();
			Model.Tick(Step, Mode, ToLearner);
			++Frames;

			Out.LargestEyeStep = FMath::Max(Out.LargestEyeStep, Distance(Eyes, Model.GetEyes()));
			Out.LargestHeadStep = FMath::Max(Out.LargestHeadStep, Distance(Head, Model.GetHead()));
			Widen(Out.EyeMin, Out.EyeMax, Model.GetEyes());
			Widen(Out.HeadMin, Out.HeadMax, Model.GetHead());

			const FStationGazeAngles Aim = Sum(Model.GetEyes(), Model.GetHead());
			if (Model.GetWeight() > 0.5f)
			{
				Out.LargestStray = FMath::Max(Out.LargestStray, Distance(Aim, ToLearner));
			}
			const bool bMeets = Model.GetWeight() > 0.9f && Distance(Aim, ToLearner) < 2.f;
			ContactFrames += bMeets ? 1 : 0;
			EyeContact = bMeets ? EyeContact + Step : 0.f;
			Out.LongestEyeContact = FMath::Max(Out.LongestEyeContact, EyeContact);

			PhaseTime += Step;
			if (Model.GetPhase() != Phase)
			{
				if (bWholePhase)
				{
					if (Phase == EStationGazePhase::Contact)
					{
						Out.ContactSeconds.Add(PhaseTime);
					}
					else if (Phase == EStationGazePhase::Away)
					{
						Out.AwaySeconds.Add(PhaseTime);
					}
				}
				Phase = Model.GetPhase();
				PhaseTime = 0.f;
				bWholePhase = true;
			}
		}
		Out.EyeContactShare = Frames > 0 ? float(ContactFrames) / Frames : 0.f;
		return Out;
	}

	/** The spread of `Values` against their mean: 0 for a fixed beat. */
	float Variation(const TArray<float>& Values)
	{
		if (Values.Num() < 2)
		{
			return 0.f;
		}
		float Mean = 0.f;
		for (float Value : Values)
		{
			Mean += Value / Values.Num();
		}
		float Variance = 0.f;
		for (float Value : Values)
		{
			Variance += FMath::Square(Value - Mean) / Values.Num();
		}
		return Mean > 0.f ? FMath::Sqrt(Variance) / Mean : 0.f;
	}

	bool AllWithin(const TArray<float>& Values, StationGaze::FSeconds Range)
	{
		// A phase ends on the frame after its time runs out.
		return !Values.ContainsByPredicate([Range](float Value)
		{
			return Value < Range.Min - FrameSeconds || Value > Range.Max + 2.f * FrameSeconds;
		});
	}
}

BEGIN_DEFINE_SPEC(FStationPatientGazeUnitSpec, "ProyectoMed.PatientGaze.Unit",
	EAutomationTestFlags::EditorContext | EAutomationTestFlags::ProductFilter)
END_DEFINE_SPEC(FStationPatientGazeUnitSpec)

void FStationPatientGazeUnitSpec::Define()
{
	Describe("the look target", [this]()
	{
		It("is the camera tagged StationView", [this]()
		{
			// A world of its own: the editor's may hold the consultation scene and its camera.
			UWorld* World = UWorld::CreateWorld(EWorldType::Game, false);
			FWorldContext& Context = GEngine->CreateNewWorldContext(EWorldType::Game);
			Context.SetCurrentWorld(World);
			World->SpawnActor<ACameraActor>();
			ACameraActor* Station = World->SpawnActor<ACameraActor>(FVector(70.f, 0.f, 120.f), FRotator::ZeroRotator);
			Station->Tags.Add(AStationPlayerController::StationViewTag);
			TestTrue("the tagged camera", UStationPatientGaze::FindLookTarget(World) == Station);
			Station->Destroy();
			TestNull("no tagged camera, no target", UStationPatientGaze::FindLookTarget(World));
			GEngine->DestroyWorldContext(World);
			World->DestroyWorld(false);
		});

		It("is measured from where the face points", [this]()
		{
			const FVector Forward = FVector::YAxisVector;
			const FVector Left = FVector::XAxisVector;
			const FVector Up = FVector::ZAxisVector;
			const FStationGazeAngles Ahead = StationGaze::AnglesOf(Forward, Left, Up, Forward);
			TestNearlyEqual("ahead: no yaw", Ahead.Yaw, 0.f, 0.01f);
			TestNearlyEqual("ahead: no pitch", Ahead.Pitch, 0.f, 0.01f);
			TestNearlyEqual("to the left", StationGaze::AnglesOf(Forward, Left, Up, FVector(1.f, 1.f, 0.f)).Yaw, 45.f, 0.01f);
			TestNearlyEqual("above", StationGaze::AnglesOf(Forward, Left, Up, FVector(0.f, 1.f, 1.f)).Pitch, 45.f, 0.01f);

			const FStationGazeAngles Angles{ -20.f, 10.f };
			const FStationGazeAngles Back = StationGaze::AnglesOf(Forward, Left, Up, StationGaze::Direction(Forward, Left, Up, Angles));
			TestNearlyEqual("round trip yaw", Back.Yaw, Angles.Yaw, 0.01f);
			TestNearlyEqual("round trip pitch", Back.Pitch, Angles.Pitch, 0.01f);
		});
	});

	Describe("who is speaking", [this]()
	{
		It("comes from the run the client already has", [this]()
		{
			using EMode = EStationGazeMode;
			TestEqual("no run", UStationPatientGaze::ModeFor(EStationRunStep::Menu, true, false, false), EMode::Off);
			TestEqual("a typed run", UStationPatientGaze::ModeFor(EStationRunStep::Running, false, false, true), EMode::Off);
			TestEqual("quiet", UStationPatientGaze::ModeFor(EStationRunStep::Running, true, false, false), EMode::Resting);
			TestEqual("the learner speaks", UStationPatientGaze::ModeFor(EStationRunStep::Running, true, true, false), EMode::Listening);
			TestEqual("the patient answers", UStationPatientGaze::ModeFor(EStationRunStep::Running, true, false, true), EMode::Answering);
			TestEqual("the learner speaks over the patient", UStationPatientGaze::ModeFor(EStationRunStep::Running, true, true, true), EMode::Listening);
			TestEqual("the run is over", UStationPatientGaze::ModeFor(EStationRunStep::Feedback, true, false, true), EMode::Off);
		});
	});

	Describe("during a spoken exchange", [this]()
	{
		for (const EStationGazeMode Mode : { EStationGazeMode::Listening, EStationGazeMode::Answering })
		{
			const FString Name = Mode == EStationGazeMode::Listening ? TEXT("listening") : TEXT("answering");

			It(FString::Printf(TEXT("looks at the learner most of the time while %s"), *Name), [this, Mode]()
			{
				FStationGazeModel Model(7);
				const FGazeRun Gaze = Run(Model, Mode, 300.f, { 3.f, 8.f });
				TestTrue(FString::Printf(TEXT("eye contact %.2f of the time"), Gaze.EyeContactShare), Gaze.EyeContactShare >= 0.6f);
			});

			It(FString::Printf(TEXT("breaks eye contact at irregular, bounded times while %s"), *Name), [this, Mode]()
			{
				FStationGazeModel Model(11);
				const FGazeRun Gaze = Run(Model, Mode, 300.f);
				TestTrue("many looks", Gaze.ContactSeconds.Num() >= 20);
				TestTrue("as many glances away", Gaze.AwaySeconds.Num() >= 20);
				TestTrue("looks within their bounds", AllWithin(Gaze.ContactSeconds, StationGaze::ContactSeconds(Mode)));
				TestTrue("glances within their bounds", AllWithin(Gaze.AwaySeconds, StationGaze::AwaySeconds(Mode)));
				TestTrue(FString::Printf(TEXT("looks vary (%.2f)"), Variation(Gaze.ContactSeconds)), Variation(Gaze.ContactSeconds) > 0.15f);
				TestTrue(FString::Printf(TEXT("glances vary (%.2f)"), Variation(Gaze.AwaySeconds)), Variation(Gaze.AwaySeconds) > 0.15f);
			});
		}

		It("listens with more eye contact than it answers", [this]()
		{
			const StationGaze::FSeconds Listening = StationGaze::ContactSeconds(EStationGazeMode::Listening);
			const StationGaze::FSeconds Answering = StationGaze::ContactSeconds(EStationGazeMode::Answering);
			TestTrue("longer looks while listening", Listening.Min + Listening.Max > Answering.Min + Answering.Max);
		});

		It("turns to the learner as soon as someone speaks", [this]()
		{
			FStationGazeModel Model(3);
			Run(Model, EStationGazeMode::Resting, 0.5f);
			Model.Tick(FrameSeconds, EStationGazeMode::Listening, {});
			TestEqual("looks at the learner", Model.GetPhase(), EStationGazePhase::Contact);
		});

		It("glances down or aside, never further than a glance", [this]()
		{
			FStationGazeModel Model(5);
			const FGazeRun Gaze = Run(Model, EStationGazeMode::Answering, 300.f);
			TestTrue(FString::Printf(TEXT("strays %.1f degrees at most"), Gaze.LargestStray),
				Gaze.LargestStray <= StationGaze::MaxGlanceDegrees + 0.5f);
		});
	});

	Describe("outside a spoken exchange", [this]()
	{
		It("rests and never stares at the learner", [this]()
		{
			FStationGazeModel Model(13);
			const FGazeRun Gaze = Run(Model, EStationGazeMode::Resting, 300.f);
			TestTrue(FString::Printf(TEXT("eye contact %.2f of the time"), Gaze.EyeContactShare), Gaze.EyeContactShare <= 0.3f);
			TestTrue(FString::Printf(TEXT("longest look %.1f s"), Gaze.LongestEyeContact),
				Gaze.LongestEyeContact <= StationGaze::ContactSeconds(EStationGazeMode::Resting).Max + 0.1f);
			TestTrue("still looks now and then", Gaze.LongestEyeContact > 0.f);
		});

		It("leaves the idle loops alone without a spoken run", [this]()
		{
			FStationGazeModel Model(17);
			Run(Model, EStationGazeMode::Listening, 5.f);
			Run(Model, EStationGazeMode::Off, 3.f);
			TestTrue("no gaze left", Model.GetWeight() < 0.01f);
			TestEqual("rests", Model.GetPhase(), EStationGazePhase::Rest);
		});
	});

	Describe("the movement", [this]()
	{
		It("never snaps, even on a long frame", [this]()
		{
			FStationGazeModel Model(19);
			const FGazeRun Gaze = Run(Model, EStationGazeMode::Answering, 120.f, { 10.f, -5.f });
			TestTrue("eyes", Gaze.LargestEyeStep <= StationGaze::EyeMaxSpeed * FrameSeconds + 0.01f);
			TestTrue("head", Gaze.LargestHeadStep <= StationGaze::HeadMaxSpeed * FrameSeconds + 0.01f);

			FStationGazeModel Slow(19);
			const FGazeRun Long = Run(Slow, EStationGazeMode::Listening, 10.f, { 20.f, 10.f }, 0.5f);
			TestTrue("eyes on a long frame", Long.LargestEyeStep <= StationGaze::EyeMaxSpeed * 0.5f + 0.01f);
			TestTrue("head on a long frame", Long.LargestHeadStep <= StationGaze::HeadMaxSpeed * 0.5f + 0.01f);
		});

		It("keeps the head and eyes within a seated person's range", [this]()
		{
			FStationGazeModel Model(23);
			const FGazeRun Gaze = Run(Model, EStationGazeMode::Listening, 60.f, { 90.f, -70.f });
			FStationGazeModel Up(23);
			const FGazeRun Above = Run(Up, EStationGazeMode::Listening, 60.f, { -90.f, 70.f });
			for (const FGazeRun* Each : { &Gaze, &Above })
			{
				TestTrue("head yaw", FMath::Max(-Each->HeadMin.Yaw, Each->HeadMax.Yaw) <= StationGaze::HeadMaxYaw + 0.01f);
				TestTrue("head up", Each->HeadMax.Pitch <= StationGaze::HeadMaxUp + 0.01f);
				TestTrue("head down", -Each->HeadMin.Pitch <= StationGaze::HeadMaxDown + 0.01f);
				TestTrue("eye yaw", FMath::Max(-Each->EyeMin.Yaw, Each->EyeMax.Yaw) <= StationGaze::EyeMaxYaw + 0.01f);
				TestTrue("eyes up", Each->EyeMax.Pitch <= StationGaze::EyeMaxUp + 0.01f);
				TestTrue("eyes down", -Each->EyeMin.Pitch <= StationGaze::EyeMaxDown + 0.01f);
			}
		});

		It("turns the head part of the way and the eyes the rest", [this]()
		{
			FStationGazeModel Model(29);
			Model.Tick(FrameSeconds, EStationGazeMode::Listening, { 12.f, 6.f });
			for (int32 Step = 0; Step < 60; ++Step)
			{
				Model.Tick(FrameSeconds, EStationGazeMode::Listening, { 12.f, 6.f });
			}
			TestTrue("the head turns", Model.GetHead().Yaw > 2.f && Model.GetHead().Pitch > 1.f);
			TestTrue("the eyes turn too", Model.GetEyes().Yaw > 2.f && Model.GetEyes().Pitch > 1.f);
			TestTrue("together they meet the learner", Distance(Sum(Model.GetHead(), Model.GetEyes()), { 12.f, 6.f }) < 0.5f);
		});
	});

	Describe("the face", [this]()
	{
		It("turns both eyes alike, with the eye-look controls only", [this]()
		{
			TMap<FName, float> Controls;
			StationGaze::EyeControls({ 15.f, -10.f }, Controls);
			TestTrue("looks left", Controls.FindRef(TEXT("CTRL_expressions_eyeLookLeftL")) > 0.f);
			TestEqual("not right", Controls.FindRef(TEXT("CTRL_expressions_eyeLookRightL")), 0.f);
			TestTrue("looks down", Controls.FindRef(TEXT("CTRL_expressions_eyeLookDownL")) > 0.f);
			TestEqual("not up", Controls.FindRef(TEXT("CTRL_expressions_eyeLookUpL")), 0.f);
			for (const TCHAR* Side : { TEXT("Left"), TEXT("Right"), TEXT("Up"), TEXT("Down") })
			{
				TestEqual(FString::Printf(TEXT("both eyes %s"), Side),
					Controls.FindRef(*FString::Printf(TEXT("CTRL_expressions_eyeLook%sL"), Side)),
					Controls.FindRef(*FString::Printf(TEXT("CTRL_expressions_eyeLook%sR"), Side)));
			}
			TestEqual("all eight controls", Controls.Num(), 8);
			for (const TPair<FName, float>& Control : Controls)
			{
				TestTrue(Control.Key.ToString(), StationGaze::IsEyeLookControl(Control.Key));
				TestFalse(FString::Printf(TEXT("%s leaves the lip sync alone"), *Control.Key.ToString()),
					StationFaceBlend::IsMouthControl(Control.Key));
				TestTrue(FString::Printf(TEXT("%s in range"), *Control.Key.ToString()), Control.Value >= 0.f && Control.Value <= 1.f);
			}

			StationGaze::EyeControls({ 400.f, -400.f }, Controls);
			for (const TPair<FName, float>& Control : Controls)
			{
				TestTrue(FString::Printf(TEXT("%s in range far off"), *Control.Key.ToString()), Control.Value >= 0.f && Control.Value <= 1.f);
			}
			TestFalse("the mouth is not an eye control", StationGaze::IsEyeLookControl(TEXT("CTRL_expressions_jawOpen")));
			TestFalse("a blink is not a look", StationGaze::IsEyeLookControl(TEXT("CTRL_expressions_eyeBlinkL")));
		});

		It("turns the neck joints about themselves", [this]()
		{
			const FQuat Parent(FRotator(30.f, 70.f, -10.f));
			const FQuat Local(FRotator(-5.f, 12.f, 40.f));
			const FQuat Turn(FVector(0.2f, 0.3f, 0.9f).GetSafeNormal(), FMath::DegreesToRadians(15.f));
			const FQuat Result = Parent * StationGaze::TurnLocal(Parent, Local, Turn);
			TestTrue("turned in component space", Result.Equals(Turn * Parent * Local, 1e-4f));
		});
	});
}

BEGIN_DEFINE_SPEC(FStationPatientGazeSceneSpec, "ProyectoMed.PatientGaze.Scene",
	EAutomationTestFlags::EditorContext | EAutomationTestFlags::ProductFilter)
	UWorld* World = nullptr;
	AActor* Patient = nullptr;
	USkeletalMeshComponent* Body = nullptr;
	USkeletalMeshComponent* Face = nullptr;
	UStationPatientGaze* Gaze = nullptr;
	FVector View;
	EStationGazeMode Mode = EStationGazeMode::Off;

	/** Advances the gaze, then the body and the face, as a frame of the game does. */
	void Step(float Seconds)
	{
		for (float Time = 0.f; Time < Seconds; Time += FrameSeconds)
		{
			Gaze->TickComponent(FrameSeconds, LEVELTICK_All, nullptr);
			for (USkeletalMeshComponent* Mesh : { Body, Face })
			{
				Mesh->TickAnimation(FrameSeconds, false);
				Mesh->RefreshBoneTransforms(nullptr);
				Mesh->FinalizeBoneTransform();
			}
		}
	}

	/** Where the face points, its left and its up, in the head joint's axes: the reference pose's +Y, +X and +Z. */
	void HeadAxes(FVector& Forward, FVector& Left, FVector& Up) const
	{
		const FReferenceSkeleton& Skeleton = Body->GetSkeletalMeshAsset()->GetRefSkeleton();
		const FQuat Head = FAnimationRuntime::GetComponentSpaceTransformRefPose(Skeleton, Skeleton.FindBoneIndex(TEXT("head"))).GetRotation();
		Forward = Head.UnrotateVector(FVector::YAxisVector);
		Left = Head.UnrotateVector(FVector::XAxisVector);
		Up = Head.UnrotateVector(FVector::ZAxisVector);
	}

	/** Degrees between where the face points and the learner's view, from between the eyes. */
	float HeadToView() const
	{
		FVector Forward, Left, Up;
		HeadAxes(Forward, Left, Up);
		const FVector Eyes = (Face->GetSocketLocation(TEXT("FACIAL_L_Eye")) + Face->GetSocketLocation(TEXT("FACIAL_R_Eye"))) * 0.5f;
		const FVector Pointing = Body->GetSocketTransform(TEXT("head")).TransformVectorNoScale(Forward);
		return FMath::RadiansToDegrees(FMath::Acos(FVector::DotProduct(Pointing.GetSafeNormal(), (View - Eyes).GetSafeNormal())));
	}

	/** Where `Eye` looks in the head: a MetaHuman eye joint looks along its +Z. */
	FStationGazeAngles EyeInHead(FName Eye) const
	{
		FVector Forward, Left, Up;
		HeadAxes(Forward, Left, Up);
		const FVector Looking = Face->GetSocketTransform(Eye).GetRotation().RotateVector(FVector::ZAxisVector);
		return StationGaze::AnglesOf(Forward, Left, Up, Face->GetSocketTransform(TEXT("head")).InverseTransformVectorNoScale(Looking));
	}

	/** Degrees between where `Eye` looks and the learner's view. */
	float EyeToView(FName Eye) const
	{
		const FTransform Now = Face->GetSocketTransform(Eye);
		const FVector Looking = Now.GetRotation().RotateVector(FVector::ZAxisVector);
		return FMath::RadiansToDegrees(FMath::Acos(FVector::DotProduct(Looking, (View - Now.GetLocation()).GetSafeNormal())));
	}
END_DEFINE_SPEC(FStationPatientGazeSceneSpec)

void FStationPatientGazeSceneSpec::Define()
{
	BeforeEach([this]()
	{
		World = UWorld::CreateWorld(EWorldType::Game, false);
		GEngine->CreateNewWorldContext(EWorldType::Game).SetCurrentWorld(World);

		// Placed as in the consultation scene (#319): facing -X, with the learner 20 degrees to its left.
		UClass* PatientClass = LoadClass<AActor>(nullptr, TEXT("/Game/Spike/MHC_Patient/BP_MHC_Patient.BP_MHC_Patient_C"));
		Patient = PatientClass ? World->SpawnActor<AActor>(PatientClass, FVector(200.f, 0.f, -38.f), FRotator(0.f, 90.f, 0.f)) : nullptr;
		if (!TestNotNull("the patient", Patient))
		{
			return;
		}
		for (UActorComponent* Component : Patient->GetComponents())
		{
			if (USkeletalMeshComponent* Mesh = Cast<USkeletalMeshComponent>(Component))
			{
				Body = Mesh->GetFName() == TEXT("Body") ? Mesh : Body;
				Face = Mesh->GetFName() == TEXT("Face") ? Mesh : Face;
			}
		}
		if (!TestNotNull("the body", Body) || !TestNotNull("the face", Face))
		{
			return;
		}
		Body->PlayAnimation(LoadObject<UAnimSequence>(nullptr, TEXT("/Game/Station/Patient/Animations/A_Patient_Sitting_Idle.A_Patient_Sitting_Idle")), true);
		UAnimSequence* FaceIdle = LoadObject<UAnimSequence>(nullptr, TEXT("/Game/Station/Patient/Animations/A_Patient_Idle_Face.A_Patient_Idle_Face"));
		Face->SetAnimationMode(EAnimationMode::AnimationBlueprint);
		Face->SetAnimInstanceClass(UStationPatientFaceAnim::StaticClass());
		Cast<UStationPatientFaceAnim>(Face->GetAnimInstance())->Setup(FaceIdle, nullptr);
		for (USkeletalMeshComponent* Mesh : { Body, Face })
		{
			Mesh->VisibilityBasedAnimTickOption = EVisibilityBasedAnimTickOption::AlwaysTickPoseAndRefreshBones;
		}

		const FVector Eyes = (Face->GetSocketLocation(TEXT("FACIAL_L_Eye")) + Face->GetSocketLocation(TEXT("FACIAL_R_Eye"))) * 0.5f;
		const float Yaw = FMath::DegreesToRadians(20.f);
		View = Eyes + 130.f * FVector(-FMath::Cos(Yaw), FMath::Sin(Yaw), 0.f);
		ACameraActor* Camera = World->SpawnActor<ACameraActor>(View, FRotator::ZeroRotator);
		Camera->Tags.Add(AStationPlayerController::StationViewTag);

		Gaze = NewObject<UStationPatientGaze>(Patient);
		Gaze->RegisterComponent();
		Mode = EStationGazeMode::Off;
		Gaze->Start(Body, Face, [this]() { return Mode; });
	});

	AfterEach([this]()
	{
		GEngine->DestroyWorldContext(World);
		World->DestroyWorld(false);
		World = nullptr;
		Patient = nullptr;
		Body = Face = nullptr;
		Gaze = nullptr;
	});

	It("turns the head and eyes to the learner, and the face goes with the head", [this]()
	{
		if (!Gaze)
		{
			return;
		}
		Step(1.f);
		const float HeadBefore = HeadToView();
		Mode = EStationGazeMode::Listening;
		Step(2.f);
		const float HeadAfter = HeadToView();
		AddInfo(FString::Printf(TEXT("head %.1f -> %.1f degrees from the learner; left eye %.1f, right eye %.1f"),
			HeadBefore, HeadAfter, EyeToView(TEXT("FACIAL_L_Eye")), EyeToView(TEXT("FACIAL_R_Eye"))));
		TestTrue("the head turns toward the learner", HeadAfter < HeadBefore - 5.f);
		TestTrue("the head turns only part of the way", HeadAfter > 3.f);
		TestTrue("the left eye meets the learner", EyeToView(TEXT("FACIAL_L_Eye")) < 3.f);
		TestTrue("the right eye meets the learner", EyeToView(TEXT("FACIAL_R_Eye")) < 3.f);
		TestTrue("the face follows the head",
			Face->GetSocketTransform(TEXT("head")).Equals(Body->GetSocketTransform(TEXT("head")), 0.1f));

		Mode = EStationGazeMode::Off;
		Step(3.f);
		TestTrue("the head goes back to the idle loop", HeadToView() > HeadBefore - 3.f);
	});

	It("turns the eyes by the angles the eye controls ask", [this]()
	{
		if (!Gaze)
		{
			return;
		}
		UStationPatientFaceAnim* FaceAnim = Cast<UStationPatientFaceAnim>(Face->GetAnimInstance());
		for (const FStationGazeAngles Asked : { FStationGazeAngles{ 20.f, 0.f }, FStationGazeAngles{ -20.f, 0.f },
			FStationGazeAngles{ 0.f, 15.f }, FStationGazeAngles{ 0.f, -15.f }, FStationGazeAngles{ 0.f, 0.f } })
		{
			// Without the gaze's own ticks, which would set the eyes again.
			FaceAnim->SetEyeGaze(Asked, 1.f);
			for (float Time = 0.f; Time < 0.5f; Time += FrameSeconds)
			{
				for (USkeletalMeshComponent* Mesh : { Body, Face })
				{
					Mesh->TickAnimation(FrameSeconds, false);
					Mesh->RefreshBoneTransforms(nullptr);
					Mesh->FinalizeBoneTransform();
				}
			}
			for (const TCHAR* Eye : { TEXT("FACIAL_L_Eye"), TEXT("FACIAL_R_Eye") })
			{
				const FStationGazeAngles Got = EyeInHead(Eye);
				const FString What = FString::Printf(TEXT("%s asked %.0f, %.0f got %.1f, %.1f"), Eye, Asked.Yaw, Asked.Pitch, Got.Yaw, Got.Pitch);
				TestTrue(What, FMath::Abs(Got.Yaw - Asked.Yaw) < 2.5f && FMath::Abs(Got.Pitch - Asked.Pitch) < 2.5f);
			}
		}
	});
}

#endif
