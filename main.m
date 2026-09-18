/* 
    Copyright (C) 2025  Serge Alagon

    This program is free software: you can redistribute it and/or modify
    it under the terms of the GNU General Public License as published by
    the Free Software Foundation, either version 3 of the License, or
    (at your option) any later version.

    This program is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU General Public License for more details.

    You should have received a copy of the GNU General Public License
    along with this program.  If not, see <https://www.gnu.org/licenses/>. 
*/

#import <objc/runtime.h>
#import <UserNotifications/UserNotifications.h>
#import <dlfcn.h>
#import "FloatingButtonWindow.h"
#import "PrivateHeaders.h"

static BOOL isImmortalized;
static BOOL isPhysicallyInBackground = NO;

static void prefsChanged() {
    isImmortalized = [[NSUserDefaults standardUserDefaults] boolForKey:@"immortalized"];
}

static void (*original_sceneID_updateWithSettingsDiff_transitionContext_completion)(id, SEL, id, id, id, id);

/* thanks to @khanhduytran0 for this wonderful hook. goat */
void new_sceneID_updateWithSettingsDiff_transitionContext_completion(id self, SEL _cmd, id arg1, id arg2, id arg3, id arg4) {
    if (!isImmortalized) {
        return original_sceneID_updateWithSettingsDiff_transitionContext_completion(self, _cmd, arg1, arg2, arg3, arg4);
    }

    NSString *diffDescription = [arg2 description];

    if ([diffDescription containsString:@"foreground = NotSet"] || 
        [diffDescription containsString:@"foreground = No"] || 
        [diffDescription containsString:@"foreground = BSSettingFlagNo"] || 
        [diffDescription containsString:@"foreground = NO"]) { 
        return;
    }

    if ([diffDescription containsString:@"hostContextIdentifierForSnapshotting = 0"] || 
        [diffDescription containsString:@"scenePresenterRenderIdentifierForSnapshotting = 0"] ||
        [diffDescription containsString:@"targetOfEventDeferringEnvironments = (empty)"]) { 
        return;
    }
    
    if ([diffDescription containsString:@"FBSceneSnapshotAction:"]) { 
        return;
    }

    return original_sceneID_updateWithSettingsDiff_transitionContext_completion(self, _cmd, arg1, arg2, arg3, arg4);
}

// MARK: - Notification & Background Overrides

static UIApplicationState (*orig_applicationState)(id, SEL);
static UIApplicationState hook_applicationState(id self, SEL _cmd) {
    if (isPhysicallyInBackground) {
        void *returnAddress = __builtin_extract_return_addr(__builtin_return_address(0));
        Dl_info info;
        if (dladdr(returnAddress, &info) && info.dli_fname) {
            NSString *imageName = [NSString stringWithUTF8String:info.dli_fname];
            if ([imageName containsString:@"UserNotifications"] || [imageName containsString:@"PushKit"]) {
                return UIApplicationStateBackground;
            }
        }
        return UIApplicationStateActive; 
    }
    return orig_applicationState ? orig_applicationState(self, _cmd) : UIApplicationStateActive;
}

static void (*orig_willPresent)(id, SEL, UNUserNotificationCenter *, UNNotification *, void (^)(UNNotificationPresentationOptions));
static void hook_willPresent(id self, SEL _cmd, UNUserNotificationCenter *center, UNNotification *notification, void (^completionHandler)(UNNotificationPresentationOptions options)) {
    if (isPhysicallyInBackground) {
        completionHandler(UNNotificationPresentationOptionBanner | UNNotificationPresentationOptionSound | UNNotificationPresentationOptionBadge);
    } else if (orig_willPresent) {
        orig_willPresent(self, _cmd, center, notification, completionHandler);
    }
}

static void (*orig_setDelegate)(id, SEL, id<UNUserNotificationCenterDelegate>);
static void hook_setDelegate(id self, SEL _cmd, id<UNUserNotificationCenterDelegate> delegate) {
    if (orig_setDelegate) orig_setDelegate(self, _cmd, delegate);
    if (delegate) {
        Class delegateClass = [delegate class];
        SEL sel = @selector(userNotificationCenter:willPresentNotification:withCompletionHandler:);
        Method method = class_getInstanceMethod(delegateClass, sel);
        if (method) {
            IMP currentIMP = method_getImplementation(method);
            if (currentIMP != (IMP)hook_willPresent) {
                orig_willPresent = (void *)currentIMP;
                method_setImplementation(method, (IMP)hook_willPresent);
            }
        }
    }
}

// MARK: - Setup

static void setup() {
    dispatch_async(dispatch_get_main_queue(), ^{
        // 1. Scene Hook
        Class targetClass = objc_getClass("FBSWorkspaceScenesClient");
        SEL originalSelector = @selector(sceneID:updateWithSettingsDiff:transitionContext:completion:);
        Method originalMethod = class_getInstanceMethod(targetClass, originalSelector);

        if (originalMethod) {
            original_sceneID_updateWithSettingsDiff_transitionContext_completion = (void (*)(id, SEL, id, id, id, id))method_getImplementation(originalMethod);
            method_setImplementation(originalMethod, (IMP)new_sceneID_updateWithSettingsDiff_transitionContext_completion);
        }

        // 2. Application State Hook
        Class uiAppClass = objc_getClass("UIApplication");
        Method appStateMethod = class_getInstanceMethod(uiAppClass, @selector(applicationState));
        if (appStateMethod) {
            orig_applicationState = (void *)method_getImplementation(appStateMethod);
            method_setImplementation(appStateMethod, (IMP)hook_applicationState);
        }

        // 3. Notification Delegate Hook
        Class unCenterClass = objc_getClass("UNUserNotificationCenter");
        Method setDelegateMethod = class_getInstanceMethod(unCenterClass, @selector(setDelegate:));
        if (setDelegateMethod) {
            orig_setDelegate = (void *)method_getImplementation(setDelegateMethod);
            method_setImplementation(setDelegateMethod, (IMP)hook_setDelegate);
        }

        // 4. Track physical background state via native notifications
        [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationDidEnterBackgroundNotification object:nil queue:nil usingBlock:^(NSNotification * _Nonnull note) {
            isPhysicallyInBackground = YES;
        }];
        
        [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationWillEnterForegroundNotification object:nil queue:nil usingBlock:^(NSNotification * _Nonnull note) {
            isPhysicallyInBackground = NO;
        }];

        CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL, (CFNotificationCallback)prefsChanged, CFSTR("com.sergy.immortalizerjailed.updateprefs"), NULL, CFNotificationSuspensionBehaviorDeliverImmediately);
        [[FloatingButtonWindow sharedInstance] showButton];
    });
}

__attribute__((constructor)) static void initialize() {
    prefsChanged();
    setup();
}
