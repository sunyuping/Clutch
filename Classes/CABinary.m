//
//  CABinary.m
//  CrackAddict
//
//  Created by Zorro on 13/11/13.
//  Copyright (c) 2013 AppAddict. All rights reserved.
//

#import "CABinary.h"
#import "CADevice.h"
#import "sha1.h"
#import "stuff.h"


#define local_arch [CADevice cpu_subtype]

#define local_cputype [CADevice cpu_type]

@interface CABinary ()
{
    NSString *oldbinaryPath;
    FILE* oldbinary;
    
    NSString *newbinaryPath;
    FILE* newbinary;
    
    BOOL credit;
    NSString *OVERDRIVE_DYLIB_PATH;
    
    NSString* sinf_file;
    NSString* supp_file;
    NSString* supf_file;
}
@end

@implementation CABinary

- (id)init
{
    return nil;
}


-(NSString *) genRandStringLength: (int) len {
    
    NSString *letters = @"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789";
    
    NSMutableString *randomString = [NSMutableString stringWithCapacity: len];
    
    for (int i=0; i<len; i++) {
        [randomString appendFormat: @"%C", [letters characterAtIndex: arc4random() % [letters length]]];
    }
    
    return randomString;
}

- (id)initWithBinary:(NSString *)thePath
{
    
    if (![NSFileManager.defaultManager fileExistsAtPath:thePath]) {
        return nil;
    }
    
    if (self = [super init]) {
        oldbinaryPath = thePath;
        overdriveEnabled = NO;
        credit = [[Prefs sharedInstance] boolForKey:@"creditFile"];
        
        NSMutableCharacterSet *charactersToRemove = [NSMutableCharacterSet alphanumericCharacterSet];
        
        [charactersToRemove formUnionWithCharacterSet:[NSMutableCharacterSet nonBaseCharacterSet]];
        //[[ NSMutableCharacterSet alphanumericCharacterSet ] invertedSet ];
        
        NSCharacterSet *charactersToRemove1 = [charactersToRemove invertedSet];
        
        NSString *trimmedReplacement =
        [[[[Prefs sharedInstance] objectForKey:@"crackerName"] componentsSeparatedByCharactersInSet:charactersToRemove1]
         componentsJoinedByString:@""];
        
        OVERDRIVE_DYLIB_PATH = [[NSString alloc]initWithFormat:@"@executable_path/%@.dylib",credit? trimmedReplacement : @"overdrive"]; //credit protection FTW
    }
    
    return self;
}

-(NSString *)readable_cputype:(cpu_type_t)type
{
    NSString *_cputype = @"unknown";
    
    if (type == CPU_TYPE_ARM) {
        _cputype = @"arm";
    }
    else if (type == CPU_TYPE_ARM64)
    {
        _cputype = @"arm64";
        
    }
    return _cputype;
}

-(NSString *)readable_cpusubtype:(cpu_subtype_t)subtype
{
    
    NSString *_cpusubtype = @"unknown";
    
    switch (subtype) {
        case CPU_SUBTYPE_ARM_V7S:
            _cpusubtype = @"armv7s";
            break;
            
        case CPU_SUBTYPE_ARM_V7:
            _cpusubtype = @"armv7";
            break;
        case CPU_SUBTYPE_ARM_V6:
            _cpusubtype = @"armv6";
            break;
        case CPU_SUBTYPE_ARM64_V8:
            _cpusubtype = @"armv8";
            break;
        case CPU_SUBTYPE_ARM64_ALL:
            _cpusubtype = @"arm64";
            break;
            
    }
    
    return _cpusubtype;
}

- (void) removeArchitecture:(struct fat_arch*) removeArch {
    struct fat_arch *lowerArch;
    fpos_t upperArchpos, lowerArchpos;
    NSString *lipoPath = [NSString stringWithFormat:@"%@_l", newbinaryPath]; // assign a new lipo path
    [[NSFileManager defaultManager] copyItemAtPath:newbinaryPath toPath:lipoPath error: NULL];
    FILE *lipoOut = fopen([lipoPath UTF8String], "r+"); // prepare the file stream
    char stripBuffer[4096];
    fseek(lipoOut, SEEK_SET, 0);
    fread(&stripBuffer, sizeof(buffer), 1, lipoOut);
    struct fat_header* fh = (struct fat_header*) (stripBuffer);
    struct fat_arch* arch = (struct fat_arch *) &fh[1];
    
    fseek(lipoOut, 8, SEEK_SET); //skip nfat_arch and bin_magic
    
    for (int i = 0; i < CFSwapInt32(fh->nfat_arch); i++) {
        //swap the one we want to strip with the next one below it
        if (arch == removeArch) {
            DEBUG("found the upperArch we want to copy!");
            fgetpos(lipoOut, &upperArchpos);
            
        }
         else if (i == (CFSwapInt32(fh->nfat_arch)) - 1) {
            DEBUG("found the lowerArch we want to copy!");
            fgetpos(lipoOut, &lowerArchpos);
            lowerArch = arch;
        }
        fseek(lipoOut, sizeof(struct fat_arch), SEEK_CUR);
        arch++;
    }
    
    //go to the upper arch location
    fseek(lipoOut, upperArchpos, SEEK_SET);
    //write the lower arch data to the upper arch poistion
    fwrite(&lowerArch, sizeof(struct fat_arch), 1, lipoOut);
    //blank the lower arch position
    fseek(lipoOut, lowerArch, SEEK_SET);
    char data[20];
    memset(data,'\0',sizeof(data));
    fwrite(&data, sizeof(data), 1, lipoOut);
    
    //change nfat_arch
    
    uint32_t bin_nfat_arch;
    
    fseek(lipoOut, 4, SEEK_SET); //bin_magic
    fread(&bin_nfat_arch, 4, 1, lipoOut); // get the number of fat architectures in the file
    DEBUG("number of architectures %u", CFSwapInt32(bin_nfat_arch));
    bin_nfat_arch = bin_nfat_arch - 0x1000000;
    
    DEBUG("number of architectures %u", CFSwapInt32(bin_nfat_arch));
    fseek(lipoOut, 4, SEEK_SET); //bin_magic
    fwrite(&bin_nfat_arch, 4, 1, lipoOut);
    
    DEBUG("Written new header to binary!");
    fclose(lipoOut);
    
    [[NSFileManager defaultManager] removeItemAtPath:newbinaryPath error:NULL];
    [[NSFileManager defaultManager] moveItemAtPath:lipoPath toPath:newbinaryPath error:NULL];
}

-(BOOL) lipoBinary:(struct fat_arch*) arch {
    
    // Lipo out the data
    NSString *lipoPath = [NSString stringWithFormat:@"%@_l", newbinaryPath]; // assign a new lipo path
    FILE *lipoOut = fopen([lipoPath UTF8String], "w+"); // prepare the file stream
    fseek(newbinary, CFSwapInt32(arch->offset), SEEK_SET); // go to the armv6 offset
    void *tmp_b = malloc(0x1000); // allocate a temporary buffer
    
    NSUInteger remain = CFSwapInt32(arch->size);
    
    while (remain > 0) {
        if (remain > 0x1000) {
            // move over 0x1000
            fread(tmp_b, 0x1000, 1, newbinary);
            fwrite(tmp_b, 0x1000, 1, lipoOut);
            remain -= 0x1000;
        } else {
            // move over remaining and break
            fread(tmp_b, remain, 1, newbinary);
            fwrite(tmp_b, remain, 1, lipoOut);
            break;
        }
    }
    
    free(tmp_b); // free temporary buffer
    fclose(lipoOut); // close lipo output stream
    fclose(newbinary); // close new binary stream
    fclose(oldbinary); // close old binary stream
    
    [[NSFileManager defaultManager] removeItemAtPath:newbinaryPath error:NULL]; // remove old file
    [[NSFileManager defaultManager] moveItemAtPath:lipoPath toPath:newbinaryPath error:NULL]; // move the lipo'd binary to the final path
    chown([newbinaryPath UTF8String], 501, 501); // adjust permissions
    chmod([newbinaryPath UTF8String], 0777); // adjust permissions
    return true;
}


- (BOOL)crackBinaryToFile:(NSString *)finalPath error:(NSError *__autoreleasing *)error {
    newbinaryPath = finalPath;
    DebugLog(@"attempting to crack binary to file! finalpath %@", finalPath);
    DebugLog(@"DEBUG: binary path %@", oldbinaryPath);
    
    if (![[NSFileManager defaultManager] copyItemAtPath:oldbinaryPath toPath:finalPath error:NULL]) {
        return NO;
    }


    DEBUG("basedir ok");
    // open streams from both files
    
	oldbinary = fopen([oldbinaryPath UTF8String], "r+");
	newbinary = fopen([finalPath UTF8String], "r+");
    DEBUG("open ok");
	
    if (oldbinary==NULL) {
        
        if (newbinary!=NULL) {
            fclose(newbinary);
        }
        
        //*error = [NSString stringWithFormat:@"[crack_binary] Error opening file: %s.\n", strerror(errno)];
        return NO;
    }
    
    fread(&buffer, sizeof(buffer), 1, oldbinary);
    
    DebugLog(@"local arch - %@",[self readable_cpusubtype:local_arch]);
    
    struct fat_header* fh  = (struct fat_header*) (buffer);
    
    switch (fh->magic) {
        //64-bit thin
        case MH_MAGIC_64: {
            struct mach_header_64 *mh64 = (struct mach_header_64 *)fh;
            
            DebugLog(@"64-bit Thin %@ binary detected",[self readable_cpusubtype:mh64->cpusubtype]);
            
            DebugLog(@"mach_header_64 %x %u %u",mh64->magic,mh64->cputype,mh64->cpusubtype);
            
            if (local_cputype == CPU_TYPE_ARM)
            {
                DebugLog(@"Can't crack 64bit on 32bit device");
                return NO;
            }
            
            if (mh64->cpusubtype != local_arch) {
                DebugLog(@"Can't crack %u on %u device",mh64->cpusubtype,local_arch);
                return NO;
            }
            
            if (![self dump64bitOrigFile:oldbinary withLocation:oldbinaryPath toFile:newbinary withTop:0]) {
                
                // Dumping failed
                DebugLog(@"Failed to dump %@",[self readable_cpusubtype:mh64->cpusubtype]);
                return NO;
            }
            return YES;
            break;
        }
        //32-bit thin
        case MH_MAGIC: {
            struct mach_header *mh32 = (struct mach_header *)fh;
            
            DebugLog(@"32bit Thin %@ binary detected",[self readable_cpusubtype:mh32->cpusubtype]);
            
            DebugLog(@"mach_header %x %u %u",mh32->magic,mh32->cputype,mh32->cpusubtype);
            
            BOOL godMode32 = NO;
            
            BOOL godMode64 = NO;
            
            if (local_cputype == CPU_TYPE_ARM64) {
                DebugLog(@"local_arch = God64");
                DebugLog(@"[TRU GOD MODE ENABLED]");
                godMode64 = YES;
                godMode32 = YES;
            }
            
            if ((!godMode64)&&(local_arch == CPU_SUBTYPE_ARM_V7S)) {
                DebugLog(@"local_arch = God32");
                DebugLog(@"[32bit GOD MODE ENABLED]");
                godMode32 = YES;
            }
            
            if ((!godMode32)&&(mh32->cpusubtype>local_arch)) {
                DebugLog(@"Can't crack 32bit(%u) on 32bit(%u) device",mh32->cpusubtype,local_arch);
                return NO;
            }
            
            if (![self dump32bitOrigFile:oldbinary withLocation:oldbinaryPath toFile:newbinary withTop:0])
            {
                // Dumping failed
                DebugLog(@"Failed to dump %@",[self readable_cpusubtype:mh32->cpusubtype]);
                return NO;
            }
            
            return YES;
            break;
        }
        //FAT
        case FAT_CIGAM: {
            NSMutableArray *stripHeaders = [NSMutableArray new];
            
            NSUInteger archCount = CFSwapInt32(fh->nfat_arch);
            
            struct fat_arch *arch = (struct fat_arch *) &fh[1]; //(struct fat_arch *) (fh + sizeof(struct fat_header));
            
            DebugLog(@"FAT binary detected");
            
            DebugLog(@"nfat_arch %lu",(unsigned long)archCount);
            
            struct fat_arch* compatibleArch;
            //loop + crack
            for (int i = 0; i < CFSwapInt32(fh->nfat_arch); i++) {
                DEBUG("currently cracking arch %u", CFSwapInt32(arch->cpusubtype));
                switch ([CADevice compatibleWith:arch]) {
                    case COMPATIBLE: {
                        DEBUG("arch compatible with device!");
                        
                        //go ahead and crack
                        if (![self dumpOrigFile:oldbinary withLocation:oldbinaryPath toFile:newbinary withArch:*arch])
                        {
                            // Dumping failed
                            
                            DebugLog(@"Cannot crack unswapped arm%u portion of binary.", CFSwapInt32(arch->cpusubtype));
                            
                            //*error = @"Cannot crack unswapped portion of binary.";
                            fclose(newbinary); // close the new binary stream
                            fclose(oldbinary); // close the old binary stream
                            [[NSFileManager defaultManager] removeItemAtPath:finalPath error:NULL]; // delete the new binary
                            return NO;
                        }
                        compatibleArch = arch;
                        break;
                        
                    }
                    case NOT_COMPATIBLE: {
                        DEBUG("arch not compatible with device!");
                        NSValue* archValue = [NSValue value:&arch withObjCType:@encode(struct fat_arch)];
                        [stripHeaders addObject:archValue];
                        break;
                    }
                    case COMPATIBLE_STRIP: {
                        DEBUG("arch compatible with device, but strip");
                        compatibleArch = arch;
                        break;
                    }
                    case COMPATIBLE_SWAP: {
                        DEBUG("arch compatible with device, but swap");
                        compatibleArch = arch;
                        break;
                    }
                }
                if ((archCount - [stripHeaders count]) == 1) {
                    DEBUG("only one architecture left!? strip");
                    if (![self lipoBinary:compatibleArch]) {
                        ERROR(@"Could not lipo binary");
                        return false;
                    }
                    return true;
                }
                arch++;
            }
            
            //strip headers
            if ([stripHeaders count] > 0) {
                for (NSValue* obj in stripHeaders) {
                    struct fat_arch* stripArch;
                    [obj getValue:&stripArch];
                    [self removeArchitecture:stripArch];
                }
            }
            break;
        }
    }
    return true;
}


- (BOOL)dumpOrigFile:(FILE *) origin withLocation:(NSString*)originPath toFile:(FILE *) target withArch:(struct fat_arch)arch
{
    if (CFSwapInt32(arch.cputype) == CPU_TYPE_ARM64) {
        DEBUG("currently cracking 64bit portion");
        return [self dump64bitOrigFile:origin withLocation:originPath toFile:target withTop:CFSwapInt32(arch.offset)];
    }
    else {
        DEBUG("currently cracking 32bit portion");
        return [self dump32bitOrigFile:origin withLocation:originPath toFile:target withTop:CFSwapInt32(arch.offset)];
    }
}

- (BOOL)dump64bitOrigFile:(FILE *) origin withLocation:(NSString*)originPath toFile:(FILE *) target withTop:(uint32_t) top
{
    fseek(target, top, SEEK_SET); // go the top of the target
    
	// we're going to be going to this position a lot so let's save it
	fpos_t topPosition;
	fgetpos(target, &topPosition);
	
	struct linkedit_data_command ldid; // LC_CODE_SIGNATURE load header (for resign)
	struct encryption_info_command_64 crypt; // LC_ENCRYPTION_INFO load header (for crypt*)
	struct mach_header_64 mach; // generic mach header
	struct load_command l_cmd; // generic load command
	struct segment_command_64 __text; // __TEXT segment
	
	struct SuperBlob *codesignblob; // codesign blob pointer
	struct CodeDirectory directory; // codesign directory index
	
	BOOL foundCrypt = FALSE;
	BOOL foundSignature = FALSE;
	BOOL foundStartText = FALSE;
	uint64_t __text_start = 0;
	uint64_t __text_size = 0;
    VERBOSE("dumping binary: analyzing load commands");
    
	fread(&mach, sizeof(struct mach_header_64), 1, target); // read mach header to get number of load commands
	for (int lc_index = 0; lc_index < mach.ncmds; lc_index++) { // iterate over each load command
        fread(&l_cmd, sizeof(struct load_command), 1, target); // read load command from binary
        //DEBUG("command: %u", CFSwapInt32(l_cmd.cmd));
        if (l_cmd.cmd == LC_ENCRYPTION_INFO_64) { // encryption info?
            fseek(target, -1 * sizeof(struct load_command), SEEK_CUR);
            fread(&crypt, sizeof(struct encryption_info_command_64), 1, target);
            VERBOSE("found cryptid");
            foundCrypt = TRUE; // remember that it was found
        } else if (l_cmd.cmd == LC_CODE_SIGNATURE) { // code signature?
            fseek(target, -1 * sizeof(struct load_command), SEEK_CUR);
            fread(&ldid, sizeof(struct linkedit_data_command), 1, target);
            VERBOSE("found code signature");
            foundSignature = TRUE; // remember that it was found
        } else if (l_cmd.cmd == LC_SEGMENT_64) {
            // some applications, like Skype, have decided to start offsetting the executable image's
            // vm regions by substantial amounts for no apparant reason. this will find the vmaddr of
            // that segment (referenced later during dumping)
            fseek(target, -1 * sizeof(struct load_command), SEEK_CUR);
            fread(&__text, sizeof(struct segment_command_64), 1, target);
            if (strncmp(__text.segname, "__TEXT", 6) == 0) {
                foundStartText = TRUE;
                VERBOSE("found start text");
                __text_start = __text.vmaddr;
                __text_size = __text.vmsize;
                
            }
            fseek(target, l_cmd.cmdsize - sizeof(struct segment_command_64), SEEK_CUR);
        } else {
            fseek(target, l_cmd.cmdsize - sizeof(struct load_command), SEEK_CUR); // seek over the load command
        }
        if (foundCrypt && foundSignature && foundStartText)
            break;
    }
    
	
	// we need to have found both of these
	if (!foundCrypt || !foundSignature || !foundStartText) {
        VERBOSE("dumping binary: some load commands were not found");
		return FALSE;
	}
	
	pid_t pid; // store the process ID of the fork
	mach_port_t port; // mach port used for moving virtual memory
	kern_return_t err; // any kernel return codes
	int status; // status of the wait
	mach_vm_size_t local_size = 0; // amount of data moved into the buffer
	uint32_t begin;
	
    VERBOSE("dumping binary: obtaining ptrace handle");
    
	// open handle to dylib loader
	void *handle = dlopen(0, RTLD_GLOBAL | RTLD_NOW);
	// load ptrace library into handle
	ptrace_ptr_t ptrace = dlsym(handle, "ptrace");
	// begin the forking process
    VERBOSE("dumping binary: forking to begin tracing");
    
	if ((pid = fork()) == 0) {
		// it worked! the magic is in allowing the process to trace before execl.
		// the process will be incapable of preventing itself from tracing
		// execl stops the process before this is capable
		// PT_DENY_ATTACH was never meant to be good security, only a minor roadblock
		
		ptrace(PT_TRACE_ME, 0, 0, 0); // trace
		execl([originPath UTF8String], "", (char *) 0); // import binary memory into executable space
        
		exit(2); // exit with err code 2 in case we could not import (this should not happen)
	} else if (pid < 0) {
        printf("error: Couldn't fork, did you compile with proper entitlements?");
		return FALSE; // couldn't fork
	} else {
		// wait until the binary stops
		do {
			wait(&status);
			if (WIFEXITED( status ))
				return FALSE;
		} while (!WIFSTOPPED( status ));
		
        VERBOSE("dumping binary: obtaining mach port");
        
		// open mach port to the other process
		if ((err = task_for_pid(mach_task_self(), pid, &port) != KERN_SUCCESS)) {
            VERBOSE("ERROR: Could not obtain mach port, did you sign with proper entitlements?");
			kill(pid, SIGKILL); // kill the fork
			return FALSE;
		}
		
        VERBOSE("dumping binary: preparing code resign");
        
		codesignblob = malloc(ldid.datasize);
		fseek(target, top + ldid.dataoff, SEEK_SET); // seek to the codesign blob
		fread(codesignblob, ldid.datasize, 1, target); // read the whole codesign blob
		uint32_t countBlobs = CFSwapInt32(codesignblob->count); // how many indexes?
		
		// iterate through each index
		for (uint32_t index = 0; index < countBlobs; index++) {
			if (CFSwapInt32(codesignblob->index[index].type) == CSSLOT_CODEDIRECTORY) { // is this the code directory?
				// we'll find the hash metadata in here
				begin = top + ldid.dataoff + CFSwapInt32(codesignblob->index[index].offset); // store the top of the codesign directory blob
				fseek(target, begin, SEEK_SET); // seek to the beginning of the blob
				fread(&directory, sizeof(struct CodeDirectory), 1, target); // read the blob
				break; // break (we don't need anything from this the superblob anymore)
			}
		}
		
		free(codesignblob); // free the codesign blob
		
		uint32_t pages = CFSwapInt32(directory.nCodeSlots); // get the amount of codeslots
		if (pages == 0) {
			kill(pid, SIGKILL); // kill the fork
			return FALSE;
		}
		
		void *checksum = malloc(pages * 20); // 160 bits for each hash (SHA1)
		uint8_t buf_d[0x1000]; // create a single page buffer
		uint8_t *buf = &buf_d[0]; // store the location of the buffer
		
        VERBOSE("dumping binary: preparing to dump");
        
		// we should only have to write and perform checksums on data that changes
		uint32_t togo = crypt.cryptsize + crypt.cryptoff;
        uint32_t total = togo;
		uint32_t pages_d = 0;
		BOOL header = TRUE;
		
		// write the header
		fsetpos(target, &topPosition);
		
		// in iOS 4.3+, ASLR can be enabled by developers by setting the MH_PIE flag in
		// the mach header flags. this will randomly offset the location of the __TEXT
		// segment, making it slightly difficult to identify the location of the
		// decrypted pages. instead of disabling this flag in the original binary
		// (which is slow, requires resigning, and requires reverting to the original
		// binary after cracking) we instead manually identify the vm regions which
		// contain the header and subsequent decrypted executable code.
		if (mach.flags & MH_PIE) {
            VERBOSE("dumping binary: ASLR enabled, identifying dump location dynamically");
			// perform checks on vm regions
			memory_object_name_t object;
			vm_region_basic_info_data_t info;
			//mach_msg_type_number_t info_count = VM_REGION_BASIC_INFO_COUNT;
            mach_msg_type_number_t info_count = VM_REGION_BASIC_INFO_COUNT_64;
			mach_vm_address_t region_start = 0;
			mach_vm_size_t region_size = 0;
			vm_region_flavor_t flavor = VM_REGION_BASIC_INFO;
			err = 0;
			
			while (err == KERN_SUCCESS) {
				err = mach_vm_region(port, &region_start, &region_size, flavor, (vm_region_info_t) &info, &info_count, &object);
				DEBUG("64-bit Region Size: %llu %u", region_size, crypt.cryptsize);
                
                if (region_size == crypt.cryptsize) {
					break;
				}
				__text_start = region_start;
				region_start += region_size;
				region_size	= 0;
			}
			if (err != KERN_SUCCESS) {
                DEBUG("mach_vm_error: %u", err);
				free(checksum);
				kill(pid, SIGKILL);
                printf("ASLR is enabled and we could not identify the decrypted memory region.\n");
				return FALSE;
				
			}
		}
		
        uint32_t headerProgress = sizeof(struct mach_header);
        uint32_t i_lcmd = 0;
        
        // overdrive dylib load command size
        uint32_t overdrive_size = sizeof(OVERDRIVE_DYLIB_PATH) + sizeof(struct dylib_command);
        overdrive_size += sizeof(long) - (overdrive_size % sizeof(long)); // load commands like to be aligned by long
        
        VERBOSE("dumping binary: performing dump");
        
		while (togo > 0) {
            // get a percentage for the progress bar
            PERCENT((int)ceil((((double)total - togo) / (double)total) * 100));
			// move an entire page into memory (we have to move an entire page regardless of whether it's a resultant or not)
			if((err = mach_vm_read_overwrite(port, (mach_vm_address_t) __text_start + (pages_d * 0x1000), (vm_size_t) 0x1000, (pointer_t) buf, &local_size)) != KERN_SUCCESS)	{
                DEBUG("dum_error: %u", err);
                VERBOSE("dumping binary: failed to dump a page");
				free(checksum); // free checksum table
				kill(pid, SIGKILL); // kill fork
				return FALSE;
			}
			
			if (header) {
                // is this the first header page?
                if (i_lcmd == 0) {
                    // is overdrive enabled?
                    if (overdriveEnabled) {
                        // prepare the mach header for the new load command (overdrive dylib)
                        ((struct mach_header *)buf)->ncmds += 1;
                        ((struct mach_header *)buf)->sizeofcmds += overdrive_size;
                        VERBOSE("dumping binary: patched mach header (overdrive)");
                    }
                }
                // iterate over the header (or resume iteration)
                void *curloc = buf + headerProgress;
                for (;i_lcmd<mach.ncmds;i_lcmd++) {
                    struct load_command *l_cmd = (struct load_command *) curloc;
                    // is the load command size in a different page?
                    uint32_t lcmd_size;
                    if ((int)(((void*)curloc - (void*)buf) + 4) == 0x1000) {
                        // load command size is at the start of the next page
                        // we need to get it
                        mach_vm_read_overwrite(port, (mach_vm_address_t) __text_start + ((pages_d+1) * 0x1000), (vm_size_t) 0x1, (pointer_t) &lcmd_size, &local_size);
                        //vm_read_overwrite(port, (mach_vm_address_t) __text_start + ((pages_d+1) * 0x1000), (vm_size_t) 0x1, (pointer_t) &lcmd_size, &local_size);
                        //printf("ieterating through header\n");
                    } else {
                        lcmd_size = l_cmd->cmdsize;
                    }
                    
                    if (l_cmd->cmd == LC_ENCRYPTION_INFO) {
                        struct encryption_info_command *newcrypt = (struct encryption_info_command *) curloc;
                        newcrypt->cryptid = 0; // change the cryptid to 0
                        VERBOSE("dumping binary: patched cryptid");
                    } else if (l_cmd->cmd == LC_SEGMENT) {
                        //printf("lc segemn yo\n");
                        struct segment_command *newseg = (struct segment_command *) curloc;
                        if (newseg->fileoff == 0 && newseg->filesize > 0) {
                            // is overdrive enabled? this is __TEXT
                            if (overdriveEnabled) {
                                // maxprot so that overdrive can change the __TEXT protection &
                                // cryptid in realtime
                                newseg->maxprot |= VM_PROT_ALL;
                                VERBOSE("dumping binary: patched maxprot (overdrive)");
                            }
                        }
                    }
                    curloc += lcmd_size;
                    if ((void *)curloc >= (void *)buf + 0x1000) {
                        //printf("skipped pass the haeder yo\n");
                        // we are currently extended past the header page
                        // offset for the next round:
                        headerProgress = (((void *)curloc - (void *)buf) % 0x1000);
                        // prevent attaching overdrive dylib by skipping
                        goto skipoverdrive;
                    }
                }
                // is overdrive enabled?
                if (overdriveEnabled) {
                    // add the overdrive dylib as long as we have room
                    if ((int8_t*)(curloc + overdrive_size) < (int8_t*)(buf + 0x1000)) {
                        VERBOSE("dumping binary: attaching overdrive DYLIB (overdrive)");
                        struct dylib_command *overdrive_dyld = (struct dylib_command *) curloc;
                        overdrive_dyld->cmd = LC_LOAD_DYLIB;
                        overdrive_dyld->cmdsize = overdrive_size;
                        overdrive_dyld->dylib.compatibility_version = OVERDRIVE_DYLIB_COMPATIBILITY_VERSION;
                        overdrive_dyld->dylib.current_version = OVERDRIVE_DYLIB_CURRENT_VER;
                        overdrive_dyld->dylib.timestamp = 2;
                        overdrive_dyld->dylib.name.offset = sizeof(struct dylib_command);

                        char *p = (char *) overdrive_dyld + overdrive_dyld->dylib.name.offset;
                        strncpy(p, OVERDRIVE_DYLIB_PATH.UTF8String, sizeof(OVERDRIVE_DYLIB_PATH));
                    }
                }
				header = FALSE;
			}
        skipoverdrive:
            //printf("attemtping to write to binary\n");
			fwrite(buf, 0x1000, 1, target); // write the new data to the target
			sha1(checksum + (20 * pages_d), buf, 0x1000); // perform checksum on the page
			//printf("doing checksum yo\n");
			togo -= 0x1000; // remove a page from the togo
            //printf("togo yo %u\n", togo);
			pages_d += 1; // increase the amount of completed pages
		}
        
        VERBOSE("dumping binary: writing new checksum");
		
		// nice! now let's write the new checksum data
		fseek(target, begin + CFSwapInt32(directory.hashOffset), SEEK_SET); // go to the hash offset
		fwrite(checksum, 20*pages_d, 1, target); // write the hashes (ONLY for the amount of pages modified)
		
		free(checksum); // free checksum table from memory
		kill(pid, SIGKILL); // kill the fork
	}
	stop_bar();
	return TRUE;

}

- (BOOL)dump32bitOrigFile:(FILE *) origin withLocation:(NSString*)originPath toFile:(FILE *) target withTop:(uint32_t) top {

    fseek(target, top, SEEK_SET); // go the top of the target
	// we're going to be going to this position a lot so let's save it
	fpos_t topPosition;
	fgetpos(target, &topPosition);
	
	struct linkedit_data_command ldid; // LC_CODE_SIGNATURE load header (for resign)
	struct encryption_info_command crypt; // LC_ENCRYPTION_INFO load header (for crypt*)
	struct mach_header mach; // generic mach header
	struct load_command l_cmd; // generic load command
	struct segment_command __text; // __TEXT segment
	
	struct SuperBlob *codesignblob; // codesign blob pointer
	struct CodeDirectory directory; // codesign directory index
	
	BOOL foundCrypt = FALSE;
	BOOL foundSignature = FALSE;
	BOOL foundStartText = FALSE;
	uint64_t __text_start = 0;
	uint64_t __text_size = 0;
    DEBUG("32bit dumping, offset %u", top);
    VERBOSE("dumping binary: analyzing load commands");
	fread(&mach, sizeof(struct mach_header), 1, target); // read mach header to get number of load commands
    
	for (int lc_index = 0; lc_index < mach.ncmds; lc_index++) { // iterate over each load command
		fread(&l_cmd, sizeof(struct load_command), 1, target); // read load command from binary
        //DEBUG("command %u", l_cmd.cmd);
		if (l_cmd.cmd == LC_ENCRYPTION_INFO) { // encryption info?
			fseek(target, -1 * sizeof(struct load_command), SEEK_CUR);
			fread(&crypt, sizeof(struct encryption_info_command), 1, target);
			foundCrypt = TRUE; // remember that it was found
		} else if (l_cmd.cmd == LC_CODE_SIGNATURE) { // code signature?
			fseek(target, -1 * sizeof(struct load_command), SEEK_CUR);
			fread(&ldid, sizeof(struct linkedit_data_command), 1, target);
			foundSignature = TRUE; // remember that it was found
		} else if (l_cmd.cmd == LC_SEGMENT) {
			// some applications, like Skype, have decided to start offsetting the executable image's
			// vm regions by substantial amounts for no apparant reason. this will find the vmaddr of
			// that segment (referenced later during dumping)
			fseek(target, -1 * sizeof(struct load_command), SEEK_CUR);
			fread(&__text, sizeof(struct segment_command), 1, target);
            
			if (strncmp(__text.segname, "__TEXT", 6) == 0) {
				foundStartText = TRUE;
				__text_start = __text.vmaddr;
				__text_size = __text.vmsize;
			}
			fseek(target, l_cmd.cmdsize - sizeof(struct segment_command), SEEK_CUR);
		} else {
			fseek(target, l_cmd.cmdsize - sizeof(struct load_command), SEEK_CUR); // seek over the load command
		}
        
        if (foundCrypt && foundSignature && foundStartText)
            break;
	}
	
	// we need to have found both of these
	if (!foundCrypt || !foundSignature || !foundStartText) {
        VERBOSE("dumping binary: some load commands were not found");
		return FALSE;
	}
	
	pid_t pid; // store the process ID of the fork
	mach_port_t port; // mach port used for moving virtual memory
	kern_return_t err; // any kernel return codes
	int status; // status of the wait
	//vm_size_t local_size = 0; // amount of data moved into the buffer
    mach_vm_size_t local_size = 0; // amount of data moved into the buffer
	uint32_t begin;
	
    VERBOSE("dumping binary: obtaining ptrace handle");
    
	// open handle to dylib loader
	void *handle = dlopen(0, RTLD_GLOBAL | RTLD_NOW);
	// load ptrace library into handle
	ptrace_ptr_t ptrace = dlsym(handle, "ptrace");
	// begin the forking process
    VERBOSE("dumping binary: forking to begin tracing");
    
	if ((pid = fork()) == 0) {
		// it worked! the magic is in allowing the process to trace before execl.
		// the process will be incapable of preventing itself from tracing
		// execl stops the process before this is capable
		// PT_DENY_ATTACH was never meant to be good security, only a minor roadblock
        
        VERBOSE("dumping binary: successfully forked");
		
		ptrace(PT_TRACE_ME, 0, 0, 0); // trace
		execl([originPath UTF8String], "", (char *) 0); // import binary memory into executable space
        
		exit(2); // exit with err code 2 in case we could not import (this should not happen)
	} else if (pid < 0) {
        printf("error: Couldn't fork, did you compile with proper entitlements?");
		return FALSE; // couldn't fork
	} else {
		// wait until the binary stops
		do {
			wait(&status);
			if (WIFEXITED( status ))
				return FALSE;
		} while (!WIFSTOPPED( status ));
		
        VERBOSE("dumping binary: obtaining mach port");
        
		// open mach port to the other process
		if ((err = task_for_pid(mach_task_self(), pid, &port) != KERN_SUCCESS)) {
            VERBOSE("ERROR: Could not obtain mach port, did you sign with proper entitlements?");
			kill(pid, SIGKILL); // kill the fork
			return FALSE;
		}
		
        VERBOSE("dumping binary: preparing code resign");
        
		codesignblob = malloc(ldid.datasize);
		fseek(target, top + ldid.dataoff, SEEK_SET); // seek to the codesign blob
		fread(codesignblob, ldid.datasize, 1, target); // read the whole codesign blob
		uint32_t countBlobs = CFSwapInt32(codesignblob->count); // how many indexes?
		
		// iterate through each index
		for (uint32_t index = 0; index < countBlobs; index++) {
			if (CFSwapInt32(codesignblob->index[index].type) == CSSLOT_CODEDIRECTORY) { // is this the code directory?
				// we'll find the hash metadata in here
				begin = top + ldid.dataoff + CFSwapInt32(codesignblob->index[index].offset); // store the top of the codesign directory blob
				fseek(target, begin, SEEK_SET); // seek to the beginning of the blob
				fread(&directory, sizeof(struct CodeDirectory), 1, target); // read the blob
				break; // break (we don't need anything from this the superblob anymore)
			}
		}
		
		free(codesignblob); // free the codesign blob
		
		uint32_t pages = CFSwapInt32(directory.nCodeSlots); // get the amount of codeslots
		if (pages == 0) {
			kill(pid, SIGKILL); // kill the fork
			return FALSE;
		}
		
		void *checksum = malloc(pages * 20); // 160 bits for each hash (SHA1)
		uint8_t buf_d[0x1000]; // create a single page buffer
		uint8_t *buf = &buf_d[0]; // store the location of the buffer
		
        VERBOSE("dumping binary: preparing to dump");
        
		// we should only have to write and perform checksums on data that changes
		uint32_t togo = crypt.cryptsize + crypt.cryptoff;
        uint32_t total = togo;
		uint32_t pages_d = 0;
		BOOL header = TRUE;
		
		// write the header
		fsetpos(target, &topPosition);
		
		// in iOS 4.3+, ASLR can be enabled by developers by setting the MH_PIE flag in
		// the mach header flags. this will randomly offset the location of the __TEXT
		// segment, making it slightly difficult to identify the location of the
		// decrypted pages. instead of disabling this flag in the original binary
		// (which is slow, requires resigning, and requires reverting to the original
		// binary after cracking) we instead manually identify the vm regions which
		// contain the header and subsequent decrypted executable code.
        
		if (mach.flags & MH_PIE) {
            VERBOSE("dumping binary: ASLR enabled, identifying dump location dynamically");
            // perform checks on vm regions
            memory_object_name_t object;
            vm_region_basic_info_data_t info;
            mach_msg_type_number_t info_count = VM_REGION_BASIC_INFO_COUNT_64; // 32/64bit :P
            mach_vm_address_t region_start = 0;
            mach_vm_size_t region_size = 0;
            vm_region_flavor_t flavor = VM_REGION_BASIC_INFO;
            err = 0;
            
            while (err == KERN_SUCCESS) {
                err = mach_vm_region(port, &region_start, &region_size, flavor, (vm_region_info_t) &info, &info_count, &object);
                
                DEBUG("32-bit Region Size: %llu %u", region_size, crypt.cryptsize);
                
                if ((uint32_t)region_size == crypt.cryptsize) {
                    break;
                }
                __text_start = region_start;
                region_start += region_size;
                region_size        = 0;
            }
            if (err != KERN_SUCCESS) {
                free(checksum);
                DEBUG("32-bit mach_vm_error: %u", err);
                printf("ASLR is enabled and we could not identify the decrypted memory region.\n");
                kill(pid, SIGKILL);
                return FALSE;
                
            }
        }
        
        
        uint32_t headerProgress = sizeof(struct mach_header);
        uint32_t i_lcmd = 0;
        
        // overdrive dylib load command size
        uint32_t overdrive_size = sizeof(OVERDRIVE_DYLIB_PATH) + sizeof(struct dylib_command);
        overdrive_size += sizeof(long) - (overdrive_size % sizeof(long)); // load commands like to be aligned by long
        
        VERBOSE("dumping binary: performing dump");
        
		while (togo > 0) {
            // get a percentage for the progress bar
            PERCENT((int)ceil((((double)total - togo) / (double)total) * 100));
            
			// move an entire page into memory (we have to move an entire page regardless of whether it's a resultant or not)
			/*if((err = vm_read_overwrite(port, (mach_vm_address_t) __text_start + (pages_d * 0x1000), (vm_size_t) 0x1000, (pointer_t) buf, &local_size)) != KERN_SUCCESS)	{
             VERBOSE("dumping binary: failed to dump a page");
             free(checksum); // free checksum table
             kill(pid, SIGKILL); // kill fork
             return FALSE;
             }*/
            
            if ((err = mach_vm_read_overwrite(port, (mach_vm_address_t) __text_start + (pages_d * 0x1000), (vm_size_t) 0x1000, (pointer_t) buf, &local_size)) != KERN_SUCCESS)	{
                
                VERBOSE("dumping binary: failed to dump a page (32)");
                
                free(checksum); // free checksum table
                kill(pid, SIGKILL); // kill the fork
                
                return FALSE;
            }
            
            
			if (header) {
                // is this the first header page?
                if (i_lcmd == 0) {
                    // is overdrive enabled?
                    if (overdriveEnabled) {
                        // prepare the mach header for the new load command (overdrive dylib)
                        ((struct mach_header *)buf)->ncmds += 1;
                        ((struct mach_header *)buf)->sizeofcmds += overdrive_size;
                        VERBOSE("dumping binary: patched mach header (overdrive)");
                    }
                }
                // iterate over the header (or resume iteration)
                void *curloc = buf + headerProgress;
                for (;i_lcmd<mach.ncmds;i_lcmd++) {
                    struct load_command *l_cmd = (struct load_command *) curloc;
                    // is the load command size in a different page?
                    uint32_t lcmd_size;
                    if ((int)(((void*)curloc - (void*)buf) + 4) == 0x1000) {
                        // load command size is at the start of the next page
                        // we need to get it
                        //vm_read_overwrite(port, (mach_vm_address_t) __text_start + ((pages_d+1) * 0x1000), (vm_size_t) 0x1, (pointer_t) &lcmd_size, &local_size);
                        mach_vm_read_overwrite(port, (mach_vm_address_t) __text_start + ((pages_d + 1) * 0x1000), (vm_size_t) 0x1, (mach_vm_address_t) &lcmd_size, &local_size);
                        //printf("ieterating through header\n");
                    } else {
                        lcmd_size = l_cmd->cmdsize;
                    }
                    
                    if (l_cmd->cmd == LC_ENCRYPTION_INFO) {
                        struct encryption_info_command *newcrypt = (struct encryption_info_command *) curloc;
                        newcrypt->cryptid = 0; // change the cryptid to 0
                        VERBOSE("dumping binary: patched cryptid");
                    } else if (l_cmd->cmd == LC_SEGMENT) {
                        //printf("lc segemn yo\n");
                        struct segment_command *newseg = (struct segment_command *) curloc;
                        if (newseg->fileoff == 0 && newseg->filesize > 0) {
                            // is overdrive enabled? this is __TEXT
                            if (overdriveEnabled) {
                                // maxprot so that overdrive can change the __TEXT protection &
                                // cryptid in realtime
                                newseg->maxprot |= VM_PROT_ALL;
                                VERBOSE("dumping binary: patched maxprot (overdrive)");
                            }
                        }
                    }
                    curloc += lcmd_size;
                    if ((void *)curloc >= (void *)buf + 0x1000) {
                        //printf("skipped pass the haeder yo\n");
                        // we are currently extended past the header page
                        // offset for the next round:
                        headerProgress = (((void *)curloc - (void *)buf) % 0x1000);
                        // prevent attaching overdrive dylib by skipping
                        goto skipoverdrive;
                    }
                }
                // is overdrive enabled?
                if (overdriveEnabled) {
                    // add the overdrive dylib as long as we have room
                    if ((int8_t*)(curloc + overdrive_size) < (int8_t*)(buf + 0x1000)) {
                        VERBOSE("dumping binary: attaching overdrive DYLIB (overdrive)");
                        struct dylib_command *overdrive_dyld = (struct dylib_command *) curloc;
                        overdrive_dyld->cmd = LC_LOAD_DYLIB;
                        overdrive_dyld->cmdsize = overdrive_size;
                        overdrive_dyld->dylib.compatibility_version = OVERDRIVE_DYLIB_COMPATIBILITY_VERSION;
                        overdrive_dyld->dylib.current_version = OVERDRIVE_DYLIB_CURRENT_VER;
                        overdrive_dyld->dylib.timestamp = 2;
                        overdrive_dyld->dylib.name.offset = sizeof(struct dylib_command);
#ifndef __LP64__
                        overdrive_dyld->dylib.name.ptr = (char *) sizeof(struct dylib_command);
#endif
                        char *p = (char *) overdrive_dyld + overdrive_dyld->dylib.name.offset;
                        strncpy(p, OVERDRIVE_DYLIB_PATH.UTF8String, OVERDRIVE_DYLIB_PATH.length);
                    }
                }
				header = FALSE;
			}
        skipoverdrive:
            //printf("attemtping to write to binary\n");
			fwrite(buf, 0x1000, 1, target); // write the new data to the target
			sha1(checksum + (20 * pages_d), buf, 0x1000); // perform checksum on the page
			//printf("doing checksum yo\n");
			togo -= 0x1000; // remove a page from the togo
            //printf("togo yo %u\n", togo);
			pages_d += 1; // increase the amount of completed pages
		}
        
        VERBOSE("dumping binary: writing new checksum");
		
		// nice! now let's write the new checksum data
		fseek(target, begin + CFSwapInt32(directory.hashOffset), SEEK_SET); // go to the hash offset
		fwrite(checksum, 20*pages_d, 1, target); // write the hashes (ONLY for the amount of pages modified)
		
		free(checksum); // free checksum table from memory
		kill(pid, SIGKILL); // kill the fork
	}
	stop_bar();
	return TRUE;
}

- (NSString *)swapArch:(NSUInteger) swaparch
{
    NSString *workingPath = oldbinaryPath;
    NSString *baseName = [oldbinaryPath lastPathComponent]; // get the basename (name of the binary)
	NSString *baseDirectory = [NSString stringWithFormat:@"%@/", [oldbinaryPath stringByDeletingLastPathComponent]]; // get the base directory
    
    char swapBuffer[4096];
    if (local_arch == OSSwapInt32(swaparch)) {
        DebugLog(@"UH HELLRO PLIS");
        return NULL;
    }
    
    NSString* suffix = [self readable_cpusubtype:OSSwapInt32(swaparch)];
    
    NSString *orig_old_path = workingPath; // save old binary path
    
    workingPath = [workingPath stringByAppendingFormat:@"_%@_lwork", suffix]; // new binary path
    [[NSFileManager defaultManager] copyItemAtPath:orig_old_path toPath:workingPath error: NULL];
    
    FILE* swapbinary = fopen([workingPath UTF8String], "r+");
    
    fseek(swapbinary, 0, SEEK_SET);
    fread(&swapBuffer, sizeof(swapBuffer), 1, swapbinary);
    struct fat_header* swapfh = (struct fat_header*) (swapBuffer);
    
    
    //moveItemAtPath:orig_old_path toPath:binaryPath error:NULL];
    // swap the architectures
    
    bool swap1 = FALSE, swap2 = FALSE;
    int i;
    
    
    struct fat_arch *swap_arch = (struct fat_arch *) &swapfh[1];
    
    DebugLog(@"arch arch arch ok ok");
    
    for (i = CFSwapInt32(swapfh->nfat_arch); i--;) {
        
        DebugLog(@"swap_arch->cpusubtype %u %u",swap_arch->cpusubtype,CFSwapInt32(swap_arch->cpusubtype));
        
        DebugLog(@"swaparch %lu %u",(unsigned long)swaparch,OSSwapInt32(swaparch));
        
        if (CFSwapInt32(swap_arch->cpusubtype) == local_arch) {
            
            swap_arch->cpusubtype = (uint32_t)swaparch;
            DebugLog(@"swap: Found local arch");
            swap1 = TRUE;
        }
        else if (swap_arch->cpusubtype == swaparch) {
            
            //shit code >___<
            if (local_cputype == CPU_TYPE_ARM64) {
                swap_arch->cpusubtype = CPU_SUBTYPE_ARM64_ALL;
            }else{
                swap_arch->cpusubtype = local_arch;
            }
            
            
            DebugLog(@"swap: swapped arch %u %u",swap_arch->cpusubtype, CFSwapInt32(swap_arch->cpusubtype));
            swap2 = TRUE;
            
        }
        swap_arch++;
    }
    
    
    // move the SC_Info keys
    NSString *scinfo_prefix = [baseDirectory stringByAppendingFormat:@"SC_Info/%@", baseName];
    sinf_file = [NSString stringWithFormat:@"%@_%@_lwork.sinf", scinfo_prefix, suffix];
    supp_file = [NSString stringWithFormat:@"%@_%@_lwork.supp", scinfo_prefix, suffix];
    DebugLog(@"sinf file yo %@", sinf_file);
    [[NSFileManager defaultManager] moveItemAtPath:[scinfo_prefix stringByAppendingString:@".sinf"] toPath:sinf_file error:NULL];
    [[NSFileManager defaultManager] moveItemAtPath:[scinfo_prefix stringByAppendingString:@".supp"] toPath:supp_file error:NULL];
    
    if (swap1 && swap2) {
        DebugLog(@"swap: Swapped both architectures");
    }
    
    fseek(swapbinary, 0, SEEK_SET);
    fwrite(swapBuffer, sizeof(swapBuffer), 1, swapbinary);
    DebugLog(@"swap: Wrote new arch info");
    fclose(swapbinary);
    return workingPath;
    
}

- (void)swapBack:(NSString *)path baseDir:(NSString *)baseDirectory baseName:(NSString *)baseName
{
    [[NSFileManager defaultManager] removeItemAtPath:path error:NULL];
    //moveItemAtPath:binaryPath toPath:orig_old_path error:NULL];
    
    //move SC_Info back
    NSString *scinfo_prefix = [baseDirectory stringByAppendingFormat:@"SC_Info/%@", baseName];
    [[NSFileManager defaultManager] moveItemAtPath:sinf_file toPath:[scinfo_prefix stringByAppendingString:@".sinf"] error:NULL];
    [[NSFileManager defaultManager] moveItemAtPath:supp_file toPath:[scinfo_prefix stringByAppendingString:@".supp"] error:NULL];
    DebugLog(@"DEBUG: Moving sinf_file %@ to %@", sinf_file, [scinfo_prefix stringByAppendingString:@".sinf"]);
}

@end

void sha1(uint8_t *hash, uint8_t *data, size_t size) {
	SHA1Context context;
	SHA1Reset(&context);
	SHA1Input(&context, data, (unsigned)size);
	SHA1Result(&context, hash);
}
