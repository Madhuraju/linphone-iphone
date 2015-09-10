/* ContactDetailsViewController.m
 *
 * Copyright (C) 2012  Belledonne Comunications, Grenoble, France
 *
 *  This program is free software; you can redistribute it and/or modify
 *  it under the terms of the GNU General Public License as published by
 *  the Free Software Foundation; either version 2 of the License, or
 *  (at your option) any later version.
 *
 *  This program is distributed in the hope that it will be useful,
 *  but WITHOUT ANY WARRANTY; without even the implied warranty of
 *  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 *  GNU General Public License for more details.
 *
 *  You should have received a copy of the GNU General Public License
 *  along with this program; if not, write to the Free Software
 *  Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA 02111-1307, USA.
 */

#import "ContactDetailsView.h"
#import "PhoneMainView.h"

@implementation ContactDetailsView

@synthesize tableController;
@synthesize contact;
@synthesize editButton;
@synthesize backButton;
@synthesize cancelButton;

static void sync_address_book(ABAddressBookRef addressBook, CFDictionaryRef info, void *context);

#pragma mark - Lifecycle Functions

- (id)init {
	self = [super initWithNibName:NSStringFromClass(self.class) bundle:[NSBundle mainBundle]];
	if (self != nil) {
		inhibUpdate = FALSE;
		addressBook = ABAddressBookCreateWithOptions(nil, nil);
		ABAddressBookRegisterExternalChangeCallback(addressBook, sync_address_book, (__bridge void *)(self));
	}
	return self;
}

- (void)dealloc {
	ABAddressBookUnregisterExternalChangeCallback(addressBook, sync_address_book, (__bridge void *)(self));
	CFRelease(addressBook);
}

#pragma mark -

- (void)resetData {
	[self disableEdit:FALSE];
	if (contact == NULL) {
		ABAddressBookRevert(addressBook);
		return;
	}

	LOGI(@"Reset data to contact %p", contact);
	ABRecordID recordID = ABRecordGetRecordID(contact);
	ABAddressBookRevert(addressBook);
	contact = ABAddressBookGetPersonWithRecordID(addressBook, recordID);
	if (contact == NULL) {
		[PhoneMainView.instance popCurrentView];
		return;
	}
	[tableController setContact:contact];
}

static void sync_address_book(ABAddressBookRef addressBook, CFDictionaryRef info, void *context) {
	ContactDetailsView *controller = (__bridge ContactDetailsView *)context;
	if (!controller->inhibUpdate && ![[controller tableController] isEditing]) {
		[controller resetData];
	}
}

- (void)removeContact {
	if (contact == NULL) {
		[PhoneMainView.instance popCurrentView];
		return;
	}

	// Remove contact from book
	if (ABRecordGetRecordID(contact) != kABRecordInvalidID) {
		CFErrorRef error = NULL;
		ABAddressBookRemoveRecord(addressBook, contact, (CFErrorRef *)&error);
		if (error != NULL) {
			LOGE(@"Remove contact %p: Fail(%@)", contact, [(__bridge NSError *)error localizedDescription]);
		} else {
			LOGI(@"Remove contact %p: Success!", contact);
		}
		contact = NULL;

		// Save address book
		error = NULL;
		inhibUpdate = TRUE;
		ABAddressBookSave(addressBook, (CFErrorRef *)&error);
		inhibUpdate = FALSE;
		if (error != NULL) {
			LOGE(@"Save AddressBook: Fail(%@)", [(__bridge NSError *)error localizedDescription]);
		} else {
			LOGI(@"Save AddressBook: Success!");
		}
		[[LinphoneManager instance].fastAddressBook reload];
	}
}

- (void)saveData {
	if (contact == NULL) {
		[PhoneMainView.instance popCurrentView];
		return;
	}

	// Add contact to book
	CFErrorRef error = NULL;
	if (ABRecordGetRecordID(contact) == kABRecordInvalidID) {
		ABAddressBookAddRecord(addressBook, contact, (CFErrorRef *)&error);
		if (error != NULL) {
			LOGE(@"Add contact %p: Fail(%@)", contact, [(__bridge NSError *)error localizedDescription]);
		} else {
			LOGI(@"Add contact %p: Success!", contact);
		}
	}

	// Save address book
	error = NULL;
	inhibUpdate = TRUE;
	ABAddressBookSave(addressBook, (CFErrorRef *)&error);
	inhibUpdate = FALSE;
	if (error != NULL) {
		LOGE(@"Save AddressBook: Fail(%@)", [(__bridge NSError *)error localizedDescription]);
	} else {
		LOGI(@"Save AddressBook: Success!");
	}
	[[LinphoneManager instance].fastAddressBook reload];
}

- (void)selectContact:(ABRecordRef)acontact andReload:(BOOL)reload {
	contact = NULL;
	[self resetData];
	contact = acontact;
	[tableController setContact:contact];

	if (reload) {
		[self enableEdit:FALSE];
		[[tableController tableView] reloadData];
	}
}

- (void)addCurrentContactContactField:(NSString *)address {
	LinphoneAddress *linphoneAddress = linphone_core_interpret_url(
		[LinphoneManager getLc], [address cStringUsingEncoding:[NSString defaultCStringEncoding]]);
	NSString *username = [NSString stringWithUTF8String:linphone_address_get_username(linphoneAddress)];

	if (([username rangeOfString:@"@"].length > 0) &&
		([[LinphoneManager instance] lpConfigBoolForKey:@"show_contacts_emails_preference"] == true)) {
		[tableController addEmailField:username];
	} else if ((linphone_proxy_config_is_phone_number(NULL, [username UTF8String])) &&
			   ([[LinphoneManager instance] lpConfigBoolForKey:@"save_new_contacts_as_phone_number"] == true)) {
		[tableController addPhoneField:username];
	} else {
		[tableController addSipField:address];
	}
	linphone_address_destroy(linphoneAddress);

	[self enableEdit:FALSE];
	[[tableController tableView] reloadData];
}

- (void)newContact {
	[self selectContact:ABPersonCreate() andReload:YES];
}

- (void)newContact:(NSString *)address {
	[self selectContact:ABPersonCreate() andReload:NO];
	[self addCurrentContactContactField:address];
}

- (void)editContact:(ABRecordRef)acontact {
	[self selectContact:ABAddressBookGetPersonWithRecordID(addressBook, ABRecordGetRecordID(acontact)) andReload:YES];
}

- (void)editContact:(ABRecordRef)acontact address:(NSString *)address {
	[self selectContact:ABAddressBookGetPersonWithRecordID(addressBook, ABRecordGetRecordID(acontact)) andReload:NO];
	[self addCurrentContactContactField:address];
}

- (void)setContact:(ABRecordRef)acontact {
	[self selectContact:ABAddressBookGetPersonWithRecordID(addressBook, ABRecordGetRecordID(acontact)) andReload:NO];
}

#pragma mark - ViewController Functions

- (void)viewWillAppear:(BOOL)animated {
	[super viewWillAppear:animated];
	if ([ContactSelection getSelectionMode] == ContactSelectionModeEdit ||
		[ContactSelection getSelectionMode] == ContactSelectionModeNone) {
		[editButton setHidden:FALSE];
	} else {
		[editButton setHidden:TRUE];
	}
}

#pragma mark - UICompositeViewDelegate Functions

static UICompositeViewDescription *compositeDescription = nil;

+ (UICompositeViewDescription *)compositeViewDescription {
	if (compositeDescription == nil) {
		compositeDescription = [[UICompositeViewDescription alloc] init:self.class
															   stateBar:StatusBarView.class
																 tabBar:TabBarView.class
															 fullscreen:false
														  landscapeMode:LinphoneManager.runningOnIpad
														   portraitMode:true];
	}
	return compositeDescription;
}

- (UICompositeViewDescription *)compositeViewDescription {
	return self.class.compositeViewDescription;
}

#pragma mark -

- (void)enableEdit:(BOOL)animated {
	if (![tableController isEditing]) {
		[tableController setEditing:TRUE animated:animated];
	}
	[editButton setOn];
	[cancelButton setHidden:FALSE];
	[backButton setHidden:TRUE];
}

- (void)disableEdit:(BOOL)animated {
	if ([tableController isEditing]) {
		[tableController setEditing:FALSE animated:animated];
	}
	[editButton setOff];
	[cancelButton setHidden:TRUE];
	[backButton setHidden:FALSE];
}

#pragma mark - Action Functions

- (IBAction)onCancelClick:(id)event {
	[self disableEdit:TRUE];
	[self resetData];
}

- (IBAction)onBackClick:(id)event {
	if ([ContactSelection getSelectionMode] == ContactSelectionModeEdit) {
		[ContactSelection setSelectionMode:ContactSelectionModeNone];
	}
	[PhoneMainView.instance popCurrentView];
}

- (IBAction)onEditClick:(id)event {
	if ([tableController isEditing]) {
		if ([tableController isValid]) {
			[self disableEdit:TRUE];
			[self saveData];
		}
	} else {
		[self enableEdit:TRUE];
	}
}

- (void)onRemove:(id)event {
	[self disableEdit:FALSE];
	[self removeContact];
	[PhoneMainView.instance popCurrentView];
}

- (void)onModification:(id)event {
	if (![tableController isEditing] || [tableController isValid]) {
		[editButton setEnabled:TRUE];
	} else {
		[editButton setEnabled:FALSE];
	}
}

@end