//
//  MoPubBinding.m
//  MoPub
//
//  Copyright (c) 2017 __MyCompanyName__. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <CoreLocation/CoreLocation.h>

#import "MoPubManager.h"


///////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark - Helpers

// Converts C style string to NSString
#define GetStringParam(_x_) ((_x_) != NULL ? [NSString stringWithUTF8String:_x_] : [NSString stringWithUTF8String:""])
#define GetNullableStringParam(_x_) ((_x_) != NULL ? [NSString stringWithUTF8String:_x_] : nil)

static double LAT_LONG_SENTINEL = 99999.0;

// Converts an NSString into a const char* ready to be sent to Unity
static char* cStringCopy(NSString* input)
{
    const char* string = [input UTF8String];
    return string ? strdup(string) : NULL;
}

static NSArray<Class<MPAdapterConfiguration>>* extractNetworkClasses(const char* networkClassesString) {
    NSString* networksString = GetStringParam(networkClassesString);
    if (networksString.length == 0)
        return nil;

    NSMutableArray* networks = [NSMutableArray array];
    for (NSString* network in [networksString componentsSeparatedByString:@","]) {
        Class networkClass = NSClassFromString(network);
        if (networkClass != Nil && [networkClass conformsToProtocol:@protocol(MPAdapterConfiguration)])
            [networks addObject:networkClass];
        else
            NSLog(@"No AdapterConfiguration class found for network class name %@", network);
    }
   return networks;
}

static NSArray<id<MPMediationSettingsProtocol>>* extractMediationSettings(const char* mediationSettingsJson) {
    NSString* jsonString = GetStringParam(mediationSettingsJson);
    if (jsonString.length == 0)
        return nil;
    NSDictionary* dict = [NSJSONSerialization JSONObjectWithData:[jsonString dataUsingEncoding:NSUTF8StringEncoding]
                                                         options:0
                                                           error:nil];
    if (dict.count == 0)
        return nil;
    NSMutableArray<id<MPMediationSettingsProtocol>>* mediationSettings = [NSMutableArray array];
    for (NSString* className in dict) {
        Class mediationSettingClass = NSClassFromString(className);
        if (mediationSettingClass == Nil || ![mediationSettingClass conformsToProtocol:@protocol(MPMediationSettingsProtocol)]) {
            NSLog(@"No MediationSettings class found for mediation settings class name %@", className);
            continue;
        }
        @try {
            NSObject<MPMediationSettingsProtocol>* mediationSetting = [mediationSettingClass new];
            NSDictionary* settings = dict[className];
            [mediationSetting setValuesForKeysWithDictionary:settings];
            [mediationSettings addObject:mediationSetting];
            NSLog(@"adding mediation settings %@ for mediation class [%@]", settings, mediationSettingClass);
        }
        @catch (NSException* e) {
            NSLog(@"Error adding mediation setting for mediation class [%@]: %@", mediationSettingClass, e);
        }
    }
    return mediationSettings;
}


static NSMutableDictionary<NSString*, NSDictionary<NSString*, id>*>* extractNetworkConfigurations(const char* networkConfigurationJson)
{
    NSString* jsonString = GetStringParam(networkConfigurationJson);
    if (jsonString.length == 0)
        return nil;
    NSMutableDictionary<NSString*, NSDictionary<NSString*, id>*>* dict =
        [NSJSONSerialization JSONObjectWithData:[jsonString dataUsingEncoding:NSUTF8StringEncoding]
                                        options:NSJSONReadingMutableContainers
                                          error:nil];
    // TODO: Check that the decoded object is actually the correct type.
    return dict.count > 0 ? dict : nil;
}


static NSMutableDictionary<NSString*, NSDictionary<NSString*, NSString*>*>* extractMoPubRequestOptions(const char* moPubRequestOptionsJson)
{
    NSString* jsonString = GetStringParam(moPubRequestOptionsJson);
    if (jsonString.length == 0)
        return nil;
    NSMutableDictionary<NSString*, NSDictionary<NSString*, NSString*>*>* dict =
        [NSJSONSerialization JSONObjectWithData:[jsonString dataUsingEncoding:NSUTF8StringEncoding]
                                        options:NSJSONReadingMutableContainers
                                          error:nil];
    // TODO: Check that the decoded object is actually the correct type.
    return dict.count > 0 ? dict : nil;
}


static void subscribeToConsentNotifications()
{
    static id observerId = nil;

    if (observerId != nil)
        [[NSNotificationCenter defaultCenter] removeObserver:observerId];
    observerId = [[NSNotificationCenter defaultCenter] addObserverForName:kMPConsentChangedNotification object:nil queue:nil usingBlock:^(NSNotification* _Nonnull note) {
            NSNumber* oldStatus = [note.userInfo objectForKey:kMPConsentChangedInfoPreviousConsentStatusKey];
            NSNumber* newStatus = [note.userInfo objectForKey:kMPConsentChangedInfoNewConsentStatusKey];
            NSNumber* canCollectPersonalInfo = [note.userInfo objectForKey:kMPConsentChangedInfoCanCollectPersonalInfoKey];
            [MoPubManager sendUnityEvent:@"EmitConsentStatusChangedEvent"
                                withArgs:@[oldStatus, newStatus, [canCollectPersonalInfo intValue] != 0 ? @"true" : @"false"]];
        }];
}


///////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark - SDK Setup

void _moPubInitializeSdk(const char* adUnitIdString,
                         const char* additionalNetworksString,
                         const char* mediationSettingsJson,
                         bool allowLegitimateInterest,
                         int logLevel,
                         const char* networkConfigurationJson,
                         const char* moPubRequestOptionsJson)
{
    subscribeToConsentNotifications();

    NSString* adUnitId = GetStringParam(adUnitIdString);
    MPMoPubConfiguration* config = [[MPMoPubConfiguration alloc] initWithAdUnitIdForAppInitialization:adUnitId];
    config.additionalNetworks = extractNetworkClasses(additionalNetworksString);
    config.globalMediationSettings = extractMediationSettings(mediationSettingsJson);
    config.allowLegitimateInterest = allowLegitimateInterest;
    config.loggingLevel = (MPLogLevel) logLevel;
    config.mediatedNetworkConfigurations = extractNetworkConfigurations(networkConfigurationJson);
    config.moPubRequestOptions = extractMoPubRequestOptions(moPubRequestOptionsJson);
    NSString* logLevelString = [[NSNumber numberWithInt:logLevel] stringValue];
    [[MoPub sharedInstance] initializeSdkWithConfiguration:config completion:^{
        [MoPubManager sendUnityEvent:@"EmitSdkInitializedEvent" withArgs:@[adUnitId, logLevelString]];
    }];
}

bool _moPubIsSdkInitialized()
{
    return MoPub.sharedInstance.isSdkInitialized;
}

const char* _moPubGetSDKVersion()
{
    return cStringCopy([MoPub sharedInstance].version);
}

void _moPubSetAllowLegitimateInterest(bool allowLegitimateInterest)
{
    [[MoPub sharedInstance] setAllowLegitimateInterest:allowLegitimateInterest];
}

bool _moPubAllowLegitimateInterest()
{
    return MoPub.sharedInstance.allowLegitimateInterest;
}

void _moPubSetLogLevel(MPLogLevel logLevel)
{
    MPLogging.consoleLogLevel = logLevel;
}

int _moPubGetLogLevel()
{
    return MPLogging.consoleLogLevel;
}

void _moPubEnableLocationSupport(bool shouldUseLocation)
{
    [[MoPubManager sharedManager] enableLocationSupport:shouldUseLocation];
}

void _moPubReportApplicationOpen(const char* iTunesAppId)
{
    [[MPAdConversionTracker sharedConversionTracker] reportApplicationOpenForApplicationID:GetStringParam(iTunesAppId)];
}

void _moPubForceWKWebView(bool shouldForce)
{
    [MoPub sharedInstance].forceWKWebView = (shouldForce ? YES : NO);
}


///////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark - Banners

void _moPubCreateBanner(int bannerType, int bannerPosition, const char* adUnitId)
{
    MoPubBannerType type = (MoPubBannerType)bannerType;
    MoPubAdPosition position = (MoPubAdPosition)bannerPosition;

    [[MoPubManager managerForAdunit:GetStringParam(adUnitId)] createBanner:type atPosition:position];
}


void _moPubShowBanner(const char* adUnitId, bool shouldShow)
{
    if (shouldShow)
        [[MoPubManager managerForAdunit:GetStringParam(adUnitId)] showBanner];
    else
        [[MoPubManager managerForAdunit:GetStringParam(adUnitId)] hideBanner:NO];
}


void _moPubRefreshBanner(const char* adUnitId, const char* keywords, const char* userDataKeywords)
{
    [[MoPubManager managerForAdunit:GetStringParam(adUnitId)] refreshAd:GetNullableStringParam(keywords)
                                                       userDataKeywords:GetNullableStringParam(userDataKeywords)];
}


void _moPubDestroyBanner(const char* adUnitId)
{
    [[MoPubManager managerForAdunit:GetStringParam(adUnitId)] destroyBanner];
}


void _moPubSetAutorefreshEnabled(const char* adUnitId, bool enabled)
{
    [[MoPubManager managerForAdunit:GetStringParam(adUnitId)] setAutorefreshEnabled:enabled];
}


void _moPubForceRefresh(const char* adUnitId)
{
    [[MoPubManager managerForAdunit:GetStringParam(adUnitId)] forceRefresh];
}


///////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark - Interstitials

void _moPubRequestInterstitialAd(const char* adUnitId, const char* keywords, const char* userDataKeywords)
{
    [[MoPubManager managerForAdunit:GetStringParam(adUnitId)] requestInterstitialAd:GetNullableStringParam(keywords)
                                                                   userDataKeywords:GetNullableStringParam(userDataKeywords)];
}


bool _moPubIsInterstitialReady(const char* adUnitId)
{
    MoPubManager* mgr = [MoPubManager managerForAdunit:GetStringParam(adUnitId)];
    return mgr != nil && [mgr interstitialIsReady];
}


void _moPubShowInterstitialAd(const char* adUnitId)
{
    [[MoPubManager managerForAdunit:GetStringParam(adUnitId)] showInterstitialAd];
}


void _moPubDestroyInterstitialAd(const char* adUnitId)
{
    [[MoPubManager managerForAdunit:GetStringParam(adUnitId)] destroyInterstitialAd];
}


///////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark - Rewarded Videos

// adVendor is required key
// AdColonyInstanceMediationSettings, (BOOL)showPrePopup, (BOOL)showPostPopup
// VungleInstanceMediationSettings, (string)userIdentifier

void _moPubRequestRewardedVideo(const char* adUnitIdStr, const char* json, const char* keywords, const char* userDataKeywords, double latitude, double longitude, const char* customerId)
{
    NSArray* mediationSettings = extractMediationSettings(json);
    CLLocation* location = nil;
    if (latitude != LAT_LONG_SENTINEL && longitude != LAT_LONG_SENTINEL)
        location = [[CLLocation alloc] initWithLatitude:latitude longitude:longitude];

    NSString* adUnitId = GetStringParam(adUnitIdStr);
    [MPRewardedVideo setDelegate:[MoPubManager managerForAdunit:adUnitId] forAdUnitId:adUnitId];
    [MPRewardedVideo loadRewardedVideoAdWithAdUnitID:adUnitId
                                            keywords:GetNullableStringParam(keywords)
                                    userDataKeywords:GetNullableStringParam(userDataKeywords)
                                            location:location
                                          customerId:GetStringParam(customerId)
                                   mediationSettings:mediationSettings];
}

bool _mopubHasRewardedVideo(const char* adUnitId)
{
    return [MPRewardedVideo hasAdAvailableForAdUnitID:GetStringParam(adUnitId)];
}

const char* _mopubGetAvailableRewards(const char* adUnitId)
{
    NSString* adUnitString = GetStringParam(adUnitId);
    NSArray* rewards = [MPRewardedVideo availableRewardsForAdUnitID:adUnitString];
    if (rewards == nil || rewards.count == 0)
        return NULL;

    // Serialize the rewards array into a comma-delimited string in the format:
    // "currency_name:currency_amount,currency_name:currency_amount,..."
    NSMutableArray* rewardStrings = [[NSMutableArray alloc] initWithCapacity:rewards.count];
    [rewards enumerateObjectsUsingBlock:^(MPRewardedVideoReward* reward, NSUInteger idx, BOOL* _Nonnull stop) {
        [rewardStrings addObject:[NSString stringWithFormat:@"%@:%d", reward.currencyType, [reward.amount intValue]]];
    }];

    NSString* rewardsString = [rewardStrings componentsJoinedByString:@","];
    return cStringCopy(rewardsString);
}

void _moPubShowRewardedVideo(const char* adUnitId, const char* currencyName, int currencyAmount, const char* customData)
{
    NSString* adUnitString = GetStringParam(adUnitId);
    if (![MPRewardedVideo hasAdAvailableForAdUnitID:adUnitString])
        NSLog(@"bailing out on showing rewarded video since it has not been loaded yet.");

    // Find the matching reward
    NSString* currency = GetStringParam(currencyName);
    __block MPRewardedVideoReward* selectedReward = nil;

    NSArray* rewards = [MPRewardedVideo availableRewardsForAdUnitID:adUnitString];
    [rewards enumerateObjectsUsingBlock:^(MPRewardedVideoReward* reward, NSUInteger idx, BOOL* _Nonnull stop) {
        if ([currency isEqualToString:reward.currencyType] && currencyAmount == [reward.amount intValue]) {
            selectedReward = reward;
            *stop = YES;
        }
    }];

    [MPRewardedVideo presentRewardedVideoAdForAdUnitID:adUnitString
                                    fromViewController:[MoPubManager unityViewController]
                                            withReward:selectedReward
                                            customData:GetNullableStringParam(customData)];
}


///////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark - User Consent

bool _moPubCanCollectPersonalInfo()
{
	return [[MoPub sharedInstance] canCollectPersonalInfo];
}

int _moPubCurrentConsentStatus()
{
	return [[MoPub sharedInstance] currentConsentStatus];
}

int _moPubIsGDPRApplicable()
{
	return [[MoPub sharedInstance] isGDPRApplicable];
}

void _moPubForceGDPRApplicable()
{
    return [[MoPub sharedInstance] forceGDPRApplicable];
}

bool _moPubShouldShowConsentDialog()
{
    return [[MoPub sharedInstance] shouldShowConsentDialog];
}

bool _moPubIsConsentDialogReady()
{
    return [[MoPub sharedInstance] isConsentDialogReady];
}

void _moPubLoadConsentDialog()
{
    [[MoPub sharedInstance] loadConsentDialogWithCompletion:^(NSError* _Nullable error) {
        if (error == nil)
            [MoPubManager sendUnityEvent:@"EmitConsentDialogLoadedEvent" withArgs:@[]];
        else
            [MoPubManager sendUnityEvent:@"EmitConsentDialogFailedEvent" withArgs:@[error.localizedDescription]];
    }];
}

void _moPubShowConsentDialog()
{
    [[MoPub sharedInstance] showConsentDialogFromViewController:[MoPubManager unityViewController] completion:^{
        [MoPubManager sendUnityEvent:@"EmitConsentDialogShownEvent" withArgs:@[]];
    }];
}

const char* _moPubCurrentConsentPrivacyPolicyUrl(const char* isoLanguageCode)
{
    NSURL* url = isoLanguageCode != nil
        ? [[MoPub sharedInstance] currentConsentPrivacyPolicyUrlWithISOLanguageCode:GetStringParam(isoLanguageCode)]
        : [[MoPub sharedInstance] currentConsentPrivacyPolicyUrl];
    return url != nil ? cStringCopy([url absoluteString]) : nil;
}

const char* _moPubCurrentConsentVendorListUrl(const char* isoLanguageCode)
{
    NSURL* url = isoLanguageCode != nil
        ? [[MoPub sharedInstance] currentConsentVendorListUrlWithISOLanguageCode:GetStringParam(isoLanguageCode)]
        : [[MoPub sharedInstance] currentConsentVendorListUrl];
    return url != nil ? cStringCopy([url absoluteString]) : nil;
}

void _moPubGrantConsent()
{
    [[MoPub sharedInstance] grantConsent];
}

void _moPubRevokeConsent()
{
    [[MoPub sharedInstance] revokeConsent];
}

const char* _moPubCurrentConsentIabVendorListFormat()
{
    return cStringCopy([[MoPub sharedInstance] currentConsentIabVendorListFormat]);
}

const char* _moPubCurrentConsentPrivacyPolicyVersion()
{
    return cStringCopy([[MoPub sharedInstance] currentConsentPrivacyPolicyVersion]);
}

const char* _moPubCurrentConsentVendorListVersion()
{
    return cStringCopy([[MoPub sharedInstance] currentConsentVendorListVersion]);
}

const char* _moPubPreviouslyConsentedIabVendorListFormat()
{
    return cStringCopy([[MoPub sharedInstance] previouslyConsentedIabVendorListFormat]);
}

const char* _moPubPreviouslyConsentedPrivacyPolicyVersion()
{
    return cStringCopy([[MoPub sharedInstance] previouslyConsentedPrivacyPolicyVersion]);
}

const char* _moPubPreviouslyConsentedVendorListVersion()
{
    return cStringCopy([[MoPub sharedInstance] previouslyConsentedVendorListVersion]);
}

