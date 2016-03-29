//
//  MoPubBinding.m
//  MoPubTest
//
//  Created by Mike DeSaro on 10/7/11.
//  Copyright (c) 2011 __MyCompanyName__. All rights reserved.
//

#import "MoPubManager.h"
#import "MoPub.h"


// Converts C style string to NSString
#define GetStringParam( _x_ ) ( _x_ != NULL ) ? [NSString stringWithUTF8String:_x_] : [NSString stringWithUTF8String:""]


void _moPubEnableLocationSupport( bool shouldUseLocation )
{
	[[MoPubManager sharedManager] enableLocationSupport:shouldUseLocation];
}


void _moPubCreateBanner( int bannerType, int bannerPosition, const char * adUnitId )
{
	MoPubBannerType type = (MoPubBannerType)bannerType;
	MoPubAdPosition position = (MoPubAdPosition)bannerPosition;
	
	[[MoPubManager sharedManager] createBanner:type atPosition:position adUnitId:GetStringParam( adUnitId )];
}


void _moPubDestroyBanner()
{
	[[MoPubManager sharedManager] destroyBanner];
}


void _moPubShowBanner( bool shouldShow )
{
	if( shouldShow )
		[[MoPubManager sharedManager] showBanner];
	else
		[[MoPubManager sharedManager] hideBanner:NO];
}


void _moPubRefreshAd( const char * keywords )
{
	NSString *keys = keywords != NULL ? GetStringParam( keywords ) : nil;
	[[MoPubManager sharedManager] refreshAd:keys];
}


///////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark - Interstitials

void _moPubRequestInterstitialAd( const char * adUnitId, const char * keywords )
{
	[[MoPubManager sharedManager] requestInterstitialAd:GetStringParam( adUnitId ) keywords:GetStringParam( keywords )];
}


void _moPubShowInterstitialAd( const char * adUnitId )
{
	[[MoPubManager sharedManager] showInterstitialAd:GetStringParam( adUnitId )];
}


void _moPubReportApplicationOpen( const char * iTunesAppId )
{
	[[MoPubManager sharedManager] reportApplicationOpen:GetStringParam( iTunesAppId )];
}


///////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark - Rewarded Videos

void _moPubInitializeRewardedVideo()
{
	[[MoPub sharedInstance] initializeRewardedVideoWithGlobalMediationSettings:nil delegate:[MoPubManager sharedManager]];
}



// adVendor is required key
// AdColonyInstanceMediationSettings, (BOOL)showPrePopup, (BOOL)showPostPopup
// VungleInstanceMediationSettings, (string)userIdentifier

void _moPubRequestRewardedVideo( const char * adUnitId, const char * json )
{
	NSMutableArray* mediationSettings = nil;

	if( json != NULL )
	{
		NSString* jsonString = GetStringParam( json );
		NSData *data = [jsonString dataUsingEncoding:NSUTF8StringEncoding];
		NSArray* array = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
		mediationSettings = [NSMutableArray array];

		for( NSDictionary* dict in array )
		{
			NSString* adVendor = [dict objectForKey:@"adVendor"];
			NSObject* mediationSetting = [NSClassFromString( [adVendor stringByAppendingString:@"InstanceMediationSettings"] ) new];

			if( !mediationSetting )
				continue;

			if( [adVendor isEqualToString:@"AdColony"] )
			{
				if( [dict.allKeys containsObject:@"showPrePopup"] )
					[mediationSetting setValue:[dict objectForKey:@"showPrePopup"] forKey:@"showPrePopup"];

				if( [dict.allKeys containsObject:@"showPostPopup"] )
					[mediationSetting setValue:[dict objectForKey:@"showPostPopup"] forKey:@"showPostPopup"];
			}
			else if( [adVendor isEqualToString:@"Vungle"] )
			{
				if( [dict.allKeys containsObject:@"userIdentifier"] )
					[mediationSetting setValue:[dict objectForKey:@"userIdentifier"] forKey:@"userIdentifier"];
			}
			else if( [adVendor isEqualToString:@"UnityAds"] )
			{
				if( [dict.allKeys containsObject:@"userIdentifier"] )
					[mediationSetting setValue:[dict objectForKey:@"userIdentifier"] forKey:@"userIdentifier"];
			}

			[mediationSettings addObject:mediationSetting];
			NSLog( @"adding mediation settings %@ for mediation class [%@]", dict, [mediationSetting class] );
		}
	}

	[MPRewardedVideo loadRewardedVideoAdWithAdUnitID:GetStringParam( adUnitId ) withMediationSettings:mediationSettings];
}


void _moPubShowRewardedVideo( const char * adUnitId )
{
	NSString *adUnitString = GetStringParam( adUnitId );
	if( ![MPRewardedVideo hasAdAvailableForAdUnitID:adUnitString] )
	{
		NSLog( @"bailing out on showing rewarded video since it has not been loaded yet." );
		//return; // removed return here
	}

	[MPRewardedVideo presentRewardedVideoAdForAdUnitID:adUnitString fromViewController:[MoPubManager unityViewController]];
}

