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

#import "PrivateHeaders.h"
#import "FloatingButton.h"
#import <objc/runtime.h>

static BOOL isImmortalized;

static void prefsChanged() {
    isImmortalized = [[NSUserDefaults standardUserDefaults] boolForKey:@"immortalized"];
}

static void (*original_sceneID_updateWithSettingsDiff_transitionContext_completion)(id, SEL, id, id, id, id);

/* thanks to @khanhduytran0 for this wonderful hook. goat */
void new_sceneID_updateWithSettingsDiff_transitionContext_completion(id self, SEL _cmd, id arg1, id arg2, id arg3, id arg4) {
    if (!isImmortalized) {
        return original_sceneID_updateWithSettingsDiff_transitionContext_completion(self, _cmd, arg1, arg2, arg3, arg4);
    }
    
    BSSettings *changes = [arg2 valueForKey:@"changes"];
    BSSettings *otherSettingsChanges = [arg2 valueForKeyPath:@"otherSettingsDiff.changes"];
    
    if([changes boolForSetting:6] || (![changes.allSettings containsIndex:6] && [[otherSettingsChanges objectForSetting:3] intValue] == 0)) {
        return original_sceneID_updateWithSettingsDiff_transitionContext_completion(self, _cmd, arg1, arg2, arg3, arg4);
    }
}

static void setup() {
    /* using didFinishLaunching is unreliable, to fix */
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ 
        Class targetClass = objc_getClass("FBSWorkspaceScenesClient");
        SEL originalSelector = @selector(sceneID:updateWithSettingsDiff:transitionContext:completion:);
        Method originalMethod = class_getInstanceMethod(targetClass, originalSelector);

        if (originalMethod) {
            original_sceneID_updateWithSettingsDiff_transitionContext_completion = (void (*)(id, SEL, id, id, id, id))method_getImplementation(originalMethod);
            method_setImplementation(originalMethod, (IMP)new_sceneID_updateWithSettingsDiff_transitionContext_completion);
        }

        UIWindow *mainWindow = nil;

        for (UIScene *scene in [UIApplication.sharedApplication connectedScenes]) {
            if ([scene isKindOfClass:[UIWindowScene class]]) {
                mainWindow = [(UIWindowScene *)scene windows].firstObject;
                break;
            }
        }
        if (mainWindow) {
            CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL, (CFNotificationCallback)prefsChanged, CFSTR("com.sergy.immortalizerjailed.updateprefs"), NULL, CFNotificationSuspensionBehaviorDeliverImmediately);
            [[FloatingButton sharedInstance] showFloatingButtonOnWindow:mainWindow];
        }
    });
}

__attribute__((constructor)) static void initialize() {
	prefsChanged();
    setup();
}