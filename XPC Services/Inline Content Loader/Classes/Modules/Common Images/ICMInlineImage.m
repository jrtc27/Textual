/* ********************************************************************* 
                  _____         _               _
                 |_   _|____  _| |_ _   _  __ _| |
                   | |/ _ \ \/ / __| | | |/ _` | |
                   | |  __/>  <| |_| |_| | (_| | |
                   |_|\___/_/\_\\__|\__,_|\__,_|_|

 Copyright (c) 2010 - 2017 Codeux Software, LLC & respective contributors.
        Please see Acknowledgements.pdf for additional information.

 Redistribution and use in source and binary forms, with or without
 modification, are permitted provided that the following conditions
 are met:

    * Redistributions of source code must retain the above copyright
      notice, this list of conditions and the following disclaimer.
    * Redistributions in binary form must reproduce the above copyright
      notice, this list of conditions and the following disclaimer in the
      documentation and/or other materials provided with the distribution.
    * Neither the name of Textual and/or "Codeux Software, LLC", nor the 
      names of its contributors may be used to endorse or promote products 
      derived from this software without specific prior written permission.

 THIS SOFTWARE IS PROVIDED BY THE AUTHOR AND CONTRIBUTORS ``AS IS'' AND
 ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
 IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
 ARE DISCLAIMED. IN NO EVENT SHALL THE AUTHOR OR CONTRIBUTORS BE LIABLE
 FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
 DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS
 OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
 HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT
 LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY
 OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF
 SUCH DAMAGE.

 *********************************************************************** */

NS_ASSUME_NONNULL_BEGIN

@interface ICMInlineImage ()
@property (nonatomic, strong, nullable) ICMInlineImageCheck *imageCheck;
@property (nonatomic, copy) NSString *finalAddress;
@end

@implementation ICMInlineImage

- (void)_performAction
{
	/* Before the image is allowed to be displayed, we check that
	 it matches user preferences. These preferences include maximum
	 filesize and maximum height. */
	ICMInlineImageCheck *imageCheck = [ICMInlineImageCheck new];

	self.imageCheck = imageCheck;

	[imageCheck checkAddress:self.finalAddress
			 completionBlock:^(BOOL safeToLoad) {
			 if (safeToLoad) {
				 [self _safeToLoadImage];
			 } else {
				 [self _unsafeToLoadImage];
			 }

			 self.imageCheck = nil;
		 }];
}

- (void)_unsafeToLoadImage
{
	self.completionBlock(self.genericValidationFailedError);
}

- (void)_safeToLoadImage
{
	ICLPayloadMutable *payload = self.payload;

	NSDictionary *templateAttributes =
	@{
		@"anchorLink" : payload.url.absoluteString,
		@"imageURL" : self.finalAddress,
		@"preferredMaximumWidth" : @([TPCPreferences inlineImagesMaxWidth]),
		@"uniqueIdentifier" : payload.uniqueIdentifier
	};

	NSError *templateRenderError = nil;

	NSString *html = [self.template renderObject:templateAttributes error:&templateRenderError];

	/* We only want to assign to the payload if we have success (HTML) */
	if (html) {
		payload.html = html;

		payload.entrypoint = self.entrypoint;

		payload.scriptResources = self.scriptResources;
	}

	self.completionBlock(templateRenderError);
}

#pragma mark -
#pragma mark Action Block

+ (nullable ICLInlineContentModuleActionBlock)actionBlockForURL:(NSURL *)url
{
	NSString *address = [self _finalAddressForURL:url];

	if (address == nil) {
		return nil;
	}

	return [self _actionBlockForFinalAddress:address];
}

+ (ICLInlineContentModuleActionBlock)_actionBlockForFinalAddress:(NSString *)address
{
	return [^(ICLInlineContentModule *module) {
		__weak ICMInlineImage *moduleTyped = module;

		moduleTyped.finalAddress = address;

		[moduleTyped _performAction];
	} copy];
}

+ (nullable NSString *)_finalAddressForURL:(NSURL *)url
{
	NSString *urlScheme = url.scheme;
	NSString *urlHost = url.host.lowercaseString;
	NSString *urlPath = url.path.percentEncodedURLPath;
	NSString *urlQuery = url.query.percentEncodedURLQuery;

	BOOL hasFileExtension = NO;

	if ([urlPath hasSuffixIgnoringCase:@".jpg"] || [urlQuery hasSuffixIgnoringCase:@".jpg"] ||
		[urlPath hasSuffixIgnoringCase:@".jpeg"] || [urlQuery hasSuffixIgnoringCase:@".jpeg"] ||
		[urlPath hasSuffixIgnoringCase:@".png"] || [urlQuery hasSuffixIgnoringCase:@".png"] ||
		[urlPath hasSuffixIgnoringCase:@".gif"] || [urlQuery hasSuffixIgnoringCase:@".gif"] ||
		[urlPath hasSuffixIgnoringCase:@".tif"] || [urlQuery hasSuffixIgnoringCase:@".tif"] ||
		[urlPath hasSuffixIgnoringCase:@".tiff"] || [urlQuery hasSuffixIgnoringCase:@".tiff"] ||
		[urlPath hasSuffixIgnoringCase:@".svg"] || [urlQuery hasSuffixIgnoringCase:@".svg"] ||
		[urlPath hasSuffixIgnoringCase:@".bmp"] || [urlQuery hasSuffixIgnoringCase:@".bmp"])
	{
		hasFileExtension = YES;

		if ([urlHost hasSuffix:@"wikipedia.org"]) {
			/* Wikipedia URLs end with a file extension but tend to be a web page.
			 There was no easy way hotlink these images at the time this exception
			 was added. This should be revisted at a later time... */

			return nil;
		} else if ([urlHost hasSuffix:@"dropbox.com"]) {
			/* Processed below */
		} else {
			return url.absoluteString;
		}
	}

	NSString *urlPathCombined = urlPath;

	if (urlQuery) {
		urlPathCombined = [urlPathCombined stringByAppendingFormat:@"?%@", urlQuery];
	}

	if ([urlHost hasSuffix:@"dropbox.com"])
	{
		if ([urlPathCombined hasPrefix:@"/s/"] && hasFileExtension) {
			return [@"https://dl.dropboxusercontent.com" stringByAppendingString:urlPathCombined];
		}
	}
	else if ([urlHost hasSuffix:@"instacod.es"])
	{
		NSObjectIsEmptyAssertReturn(urlPath, nil);

		NSString *s = [urlPath substringFromIndex:1];

		if (s.numericOnly) {
			return [@"http://instacod.es/file/" stringByAppendingString:s];
		}
	}
	else if ([urlHost isEqualToString:@"pbs.twimg.com"])
	{
		NSObjectIsEmptyAssertReturn(urlPath, nil);

		urlPath = [urlPath
				   stringByReplacingOccurrencesOfString:@"\\:(large|medium|orig|small|thumb)$"
										     withString:@""
											    options:NSRegularExpressionSearch
											      range:urlPath.range];

		return [NSString stringWithFormat:@"https://pbs.twimg.com/%@:orig", urlPath];
	}
	else if ([urlHost isEqualToString:@"docs.google.com"])
	{
		if ([urlPath hasPrefix:@"/file/d/"] == NO) {
			return nil;
		}

		NSString *photoId = nil;

		NSArray *components = [urlPath componentsSeparatedByString:@"/"];

		if (components.count == 5) {
			if ([components[4] isEqualToString:@"edit"]) { // Add a little validation
				photoId = components[3];
			}
		} else if (components.count == 4) {
			photoId = components[3];
		} else {
			return nil;
		}

		if (photoId) {
			return [@"https://docs.google.com/uc?id=" stringByAppendingString:photoId];
		}
	}
	else if ([urlHost hasSuffix:@"twitpic.com"])
	{
		NSObjectIsEmptyAssertReturn(urlPath, nil);

		NSString *s = [urlPath substringFromIndex:1];

		if ([s hasSuffix:@"/full"]) {
			s = [s substringToIndex:(s.length - 5)];
		}

		if (s.alphabeticNumericOnly) {
			return [NSString stringWithFormat:@"http://twitpic.com/show/large/%@", s];
		}
	}
	else if ([urlHost hasSuffix:@"cl.ly"])
	{
		NSObjectIsEmptyAssertReturn(urlPath, nil);

		NSString *s = [urlPath substringFromIndex:1];

		NSArray *components = [s componentsSeparatedByString:@"/"];

		if (components.count != 2) {
			return nil;
		}

		NSString *p1 = components[0];
		NSString *p2 = components[1];

		if ([p1 isEqualIgnoringCase:@"image"]) {
			return [NSString stringWithFormat:@"http://cl.ly/%@/content", p2];
		}
	}
	else if ([urlHost hasSuffix:@"instagram.com"] ||
			 [urlHost hasSuffix:@"instagr.am"])
	{
		NSObjectIsEmptyAssertReturn(urlPath, nil);

		if ([urlPath hasPrefix:@"/p/"] == NO) {
			return nil;
		}

		NSString *s = [urlPath substringFromIndex:3];

		if ([s onlyContainsCharacters:CS_AtoZUnderscoreDashCharacters]) {
			return [NSString stringWithFormat:@"https://www.instagram.com/p/%@/media/?size=l", s];
		}
	}
	else if ([urlHost hasSuffix:@"leetfil.es"] ||
			 [urlHost hasSuffix:@"lfil.es"] ||
			 [urlHost hasSuffix:@"i.leetfil.es"])
	{
		NSObjectIsEmptyAssertReturn(urlPath, nil);

		if ([urlHost hasSuffix:@"i.leetfil.es"]) {
			NSString *s = [urlPath substringFromIndex:1];

			if (s.alphabeticNumericOnly) {
				return [NSString stringWithFormat:@"https://i.leetfil.es/%@", s];
			}
		} else if ([urlHost hasSuffix:@"lfil.es"]) {
			if ([urlPath hasPrefix:@"/i/"]) {
				NSString *s = [urlPath substringFromIndex:3];

				if (s.alphabeticNumericOnly) {
					return [NSString stringWithFormat:@"https://i.leetfil.es/%@", s];
				}
			} else if ([urlPath hasPrefix:@"/v/"]) {
				NSString *v = [urlPath substringFromIndex:3];

				if (v.alphabeticNumericOnly) {
					return [NSString stringWithFormat:@"https://v.leetfil.es/%@_thumb", v];
				}
			}
		} else {
			if ([urlPath hasPrefix:@"/image/"]) {
				NSString *s = [urlPath substringFromIndex:7];

				if (s.alphabeticNumericOnly) {
					return [NSString stringWithFormat:@"https://i.leetfil.es/%@", s];
				}
			} else if ([urlPath hasPrefix:@"/video/"]) {
				NSString *v = [urlPath substringFromIndex:7];

				if (v.alphabeticNumericOnly) {
					return [NSString stringWithFormat:@"https://v.leetfil.es/%@_thumb", v];
				}
			}
		}
	}
	else if ([urlHost hasSuffix:@"arxius.io"] ||
			 [urlHost hasSuffix:@"i.arxius.io"] ||
			 [urlHost hasSuffix:@"v.arxius.io"])
	{
		NSObjectIsEmptyAssertReturn(urlPath, nil);

		if ([urlHost hasSuffix:@"i.arxius.io"]) {
			NSString *s = [urlPath substringFromIndex:1];

			if (s.alphabeticNumericOnly) {
				return [NSString stringWithFormat:@"https://i.arxius.io/%@", s];
			}
		} else if ([urlHost hasSuffix:@"v.arxius.io"]) {
			NSString *v = [urlPath substringFromIndex:1];

			if (v.alphabeticNumericOnly) {
				return [NSString stringWithFormat:@"https://v.arxius.io/%@_thumb", v];
			}
		} else {
			if ([urlPath hasPrefix:@"/i/"]) {
				NSString *s = [urlPath substringFromIndex:3];

				if (s.alphabeticNumericOnly) {
					return [NSString stringWithFormat:@"https://i.arxius.io/%@", s];
				}
			} else if ([urlPath hasPrefix:@"/v/"]) {
				NSString *v = [urlPath substringFromIndex:3];

				if (v.alphabeticNumericOnly) {
					return [NSString stringWithFormat:@"https://v.arxius.io/%@_thumb", v];
				}
			}
		}
	}
	else if ([urlHost hasSuffix:@"i.4cdn.org"])
	{
		NSObjectIsEmptyAssertReturn(urlPath, nil);

		if ([urlPath hasSuffix:@".webm"] == NO) {
			return nil;
		}

		NSString *filenameWithoutExtension = urlPath.stringByDeletingPathExtension;

		return [NSString stringWithFormat:@"%@://%@%@s.jpg", urlScheme, urlHost, filenameWithoutExtension];
	}
	else if ([urlHost hasSuffix:@"8ch.net"])
	{
		NSObjectIsEmptyAssertReturn(urlPath, nil);

		if ([urlPath hasSuffix:@".webm"] == NO) {
			return nil;
		}

		NSString *filename = urlPath.lastPathComponent;

		NSString *filenameWithoutExtension = filename.stringByDeletingPathExtension;

		return [NSString stringWithFormat:@"%@://%@/webm/thumb/%@.jpg", urlScheme, urlHost, filenameWithoutExtension];
	}
	else if ([urlHost hasSuffix:@"movapic.com"])
	{
		if ([urlPath hasPrefix:@"/pic/"] == NO) {
			return nil;
		}

		NSString *s = [urlPath substringFromIndex:5];

		if (s.alphabeticNumericOnly) {
			return [NSString stringWithFormat:@"http://image.movapic.com/pic/m_%@.jpeg", s];
		}
	}
	else if ([urlHost hasSuffix:@"f.hatena.ne.jp"])
	{
		NSArray *components = [urlPath componentsSeparatedByString:@"/"];

		if (components.count < 3) {
			return nil;
		}

		NSString *userId = components[1];
		NSString *photoId = components[2];

		if (userId.length == 0 || photoId.length < 8) {
			return nil;
		}

		if (photoId.numericOnly == NO) {
			return nil;
		}

		NSString *userIdHead = [userId substringToIndex:1];
		NSString *photoIdHead = [photoId substringToIndex:8];

		return [NSString stringWithFormat:@"http://img.f.hatena.ne.jp/images/fotolife/%@/%@/%@/%@.jpg", userIdHead, userId, photoIdHead, photoId];
	}
	else if ([urlHost isEqualToString:@"puu.sh"])
	{
		NSObjectIsEmptyAssertReturn(urlPath, nil);

		NSString *s = [urlPath substringFromIndex:1];

		if (s.alphabeticNumericOnly) {
			return [NSString stringWithFormat:@"http://puu.sh/%@.jpg", s];
		}
	}
	else if ([urlHost hasSuffix:@"d.pr"])
	{
		if ([urlPath hasPrefix:@"/i/"] == NO) {
			return nil;
		}

		NSString *s = [urlPath substringFromIndex:3];

		if (s.alphabeticNumericOnly) {
			return [NSString stringWithFormat:@"http://d.pr/i/%@.png", s];
		}
	}
	else if ([urlHost hasSuffix:@"youtube.com"] ||
			 [urlHost isEqualToString:@"youtu.be"])
	{
		NSObjectIsEmptyAssertReturn(urlPath, nil)

		NSString *videoId = nil;

		if ([urlHost isEqualToString:@"youtu.be"]) {
			videoId = [urlPath substringFromIndex:1];
		} else {
			NSDictionary *queryItems = urlQuery.URLQueryItems;

			videoId = queryItems[@"v"];
		}

		if (videoId.length < 11) {
			return nil;
		}

		if (videoId.length > 11) {
			videoId = [videoId substringToIndex:11];
		}

		return [NSString stringWithFormat:@"http://i.ytimg.com/vi/%@/mqdefault.jpg", videoId];
	}
	else if ([urlHost hasSuffix:@"nicovideo.jp"] ||
			 [urlHost isEqualToString:@"nico.ms"])
	{
		NSObjectIsEmptyAssertReturn(urlPath, nil)

		NSString *videoId = nil;

		NSString *s = nil;

		if ([urlHost isEqualToString:@"nico.ms"]) {
			s = [urlPath substringFromIndex:1];
		} else if ([urlPath hasPrefix:@"/watch/"]) {
			s = [urlPath substringFromIndex:7];
		}

		if ([s hasPrefix:@"sm"] || [s hasPrefix:@"nm"]) {
			videoId = s;
		}

		if (videoId.length < 3) {
			return nil;
		}

		long long videoNumber = [videoId substringFromIndex:2].longLongValue;

		return [NSString stringWithFormat:@"http://tn-skr%lli.smilevideo.jp/smile?i=%lli", ((videoNumber % 4) + 1), videoNumber];
	}
	else if ([urlHost isEqualToString:@"i.reddituploads.com"])
	{
		NSObjectIsEmptyAssertReturn(urlPath, nil);

		NSString *s = [urlPath substringFromIndex:1];

		if (s.alphabeticNumericOnly) {
			return url.absoluteString;
		}
	}
	else if ([urlPath hasPrefix:@"/image/"])
	{
		/* Try our best to regonize cl.ly custom domains. */
		NSString *s = [urlPath substringFromIndex:7];

		if (s.length != 12) {
			return nil;
		}

		if (s.alphabeticNumericOnly) {
			return [NSString stringWithFormat:@"http://cl.ly/%@/content", s];
		}
	}

	return nil;
}

#pragma mark -
#pragma mark Utilities

- (nullable GRMustacheTemplate *)template
{
	static GRMustacheTemplate *template = nil;
	
	static dispatch_once_t onceToken;
	
	dispatch_once(&onceToken, ^{
		/* So you may wonder why the subfolder is named "Components" when these
		 are referred to as "Modules" — well it turns out Apple doesn't like the
		 latter. When that was used as a folder name, it would not appear in the
		 Resources folder of the service when copied to the main app. */
		NSString *templatePath =
		[RZMainBundle() pathForResource:@"ICMInlineImage" ofType:@"mustache" inDirectory:@"Components"];
		
		/* This module isn't designed to handle GRMustacheTemplate ever returning a
		 nil value, but if it ever happens, we log error to better understand why. */
		NSError *templateLoadError;
		
		template = [GRMustacheTemplate templateFromContentsOfFile:templatePath error:&templateLoadError];
		
		if (template == nil) {
			LogToConsoleError("Failed to load template '%@': %@",
				templatePath, templateLoadError.localizedDescription);
		}
	});
	
	return template;
}

- (nullable NSArray<NSString *> *)scriptResources
{
	static NSArray<NSString *> *scriptResources = nil;
	
	static dispatch_once_t onceToken;
	
	dispatch_once(&onceToken, ^{
		scriptResources =
		@[
		  [RZMainBundle() pathForResource:@"InlineImageLiveResize" ofType:@"js"],
		  [RZMainBundle() pathForResource:@"ICMInlineImage" ofType:@"js" inDirectory:@"Components"]
		];
	});
	
	return scriptResources;
}

- (nullable NSString *)entrypoint
{
	return @"_ICMInlineImage.entrypoint";
}

+ (NSArray<NSString *> *)validImageContentTypes
{
	static NSArray<NSString *> *cachedValue = nil;
	
	static dispatch_once_t onceToken;
	
	dispatch_once(&onceToken, ^{
		cachedValue =
		@[@"image/gif",
		  @"image/jpeg",
		  @"image/png",
		  @"image/svg+xml",
		  @"image/tiff",
		  @"image/x-ms-bmp"];
	});
	
	return cachedValue;
}

@end

NS_ASSUME_NONNULL_END
