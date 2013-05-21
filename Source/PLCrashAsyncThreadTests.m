/*
 * Author: Landon Fuller <landonf@plausiblelabs.com>
 *
 * Copyright (c) 2008-2013 Plausible Labs Cooperative, Inc.
 * All rights reserved.
 *
 * Permission is hereby granted, free of charge, to any person
 * obtaining a copy of this software and associated documentation
 * files (the "Software"), to deal in the Software without
 * restriction, including without limitation the rights to use,
 * copy, modify, merge, publish, distribute, sublicense, and/or sell
 * copies of the Software, and to permit persons to whom the
 * Software is furnished to do so, subject to the following
 * conditions:
 *
 * The above copyright notice and this permission notice shall be
 * included in all copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
 * EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES
 * OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
 * NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT
 * HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY,
 * WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
 * FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR
 * OTHER DEALINGS IN THE SOFTWARE.
 */

#import "GTMSenTestCase.h"

#import "PLCrashAsyncThread.h"
#import "PLCrashTestThread.h"

#import <pthread.h>

@interface PLCrashAsyncThreadTests : SenTestCase {
@private
    plcrash_test_thread_t _thr_args;
}

@end

@implementation PLCrashAsyncThreadTests


- (void) setUp {
    plcrash_test_thread_spawn(&_thr_args);
}

- (void) tearDown {
    plcrash_test_thread_stop(&_thr_args);
}

- (void) testGetRegName {
    plcrash_async_thread_state_t ts;
    plcrash_async_thread_state_mach_thread_init(&ts, pthread_mach_thread_np(_thr_args.thread));
    
    for (int i = 0; i < plcrash_async_thread_state_get_reg_count(&ts); i++) {
        const char *name = plcrash_async_thread_state_get_reg_name(&ts, i);
        STAssertNotNULL(name, @"Register name for %d is NULL", i);
        STAssertNotEquals((size_t)0, strlen(name), @"Register name for %d is 0 length", i);
        STAssertNotEquals((uint32_t)PLCRASH_REG_INVALID, (uint32_t)i, @"Register name is assigned to invalid pseudo-register");
    }
}

- (void) testGetSetRegister {
    plcrash_async_thread_state_t ts;
    plcrash_async_thread_state_mach_thread_init(&ts, pthread_mach_thread_np(_thr_args.thread));
    size_t regcount = plcrash_async_thread_state_get_reg_count(&ts);

    /* Verify that all registers are marked as available */
    STAssertTrue(__builtin_popcount(ts.valid_regs) >= regcount, @"Incorrect number of 1 bits");
    for (int i = 0; i < plcrash_async_thread_state_get_reg_count(&ts); i++) {
        STAssertTrue(plcrash_async_thread_state_has_reg(&ts, i), @"Register should be marked as set");
    }

    /* Clear all registers */
    plcrash_async_thread_state_clear_all_regs(&ts);
    STAssertEquals(ts.valid_regs, (uint32_t)0, @"Registers not marked as clear");

    /* Now set+get each individually */
    for (int i = 0; i < plcrash_async_thread_state_get_reg_count(&ts); i++) {
        plcrash_greg_t reg;
        
        plcrash_async_thread_state_set_reg(&ts, i, 5);
        reg = plcrash_async_thread_state_get_reg(&ts, i);
        STAssertEquals(reg, (plcrash_greg_t)5, @"Unexpected register value");
        
        STAssertTrue(plcrash_async_thread_state_has_reg(&ts, i), @"Register should be marked as set");
        STAssertEquals(__builtin_popcount(ts.valid_regs), i+1, @"Incorrect number of 1 bits");
    }
}

/* Test plcrash_async_thread_state_init() */
- (void) testEmptyInit {
    plcrash_async_thread_state_t ts;

#if PLCRASH_ASYNC_THREAD_X86_SUPPORT
    STAssertEquals(plcrash_async_thread_state_init(&ts, CPU_TYPE_X86), PLCRASH_ESUCCESS, @"Failed to initialize thread state");
    STAssertEquals(ts.x86_state.thread.tsh.count, (int)x86_THREAD_STATE32_COUNT, @"Incorrect count");
    STAssertEquals(ts.x86_state.thread.tsh.flavor, x86_THREAD_STATE32, @"Incorrect flavor");
    STAssertEquals(ts.x86_state.exception.esh.count, (int)x86_EXCEPTION_STATE32_COUNT, @"Incorrect count");
    STAssertEquals(ts.x86_state.exception.esh.flavor, x86_EXCEPTION_STATE32, @"Incorrect flavor");
    STAssertEquals(ts.stack_direction, PLCRASH_ASYNC_THREAD_STACK_DIRECTION_DOWN, @"Incorrect stack direction");
    STAssertEquals(ts.greg_size, (size_t)4, @"Incorrect gpreg size");

    STAssertEquals(plcrash_async_thread_state_init(&ts, CPU_TYPE_X86_64), PLCRASH_ESUCCESS, @"Failed to initialize thread state");
    STAssertEquals(ts.x86_state.thread.tsh.count, (int)x86_THREAD_STATE64_COUNT, @"Incorrect count");
    STAssertEquals(ts.x86_state.thread.tsh.flavor, x86_THREAD_STATE64, @"Incorrect flavor");
    STAssertEquals(ts.x86_state.exception.esh.count, (int)x86_EXCEPTION_STATE64_COUNT, @"Incorrect count");
    STAssertEquals(ts.x86_state.exception.esh.flavor, x86_EXCEPTION_STATE64, @"Incorrect flavor");
    STAssertEquals(ts.stack_direction, PLCRASH_ASYNC_THREAD_STACK_DIRECTION_DOWN, @"Incorrect stack direction");
    STAssertEquals(ts.greg_size, (size_t)8, @"Incorrect gpreg size");
#endif /* PLCRASH_ASYNC_THREAD_X86_SUPPORT */

#if PLCRASH_ASYNC_THREAD_ARM_SUPPORT
    STAssertEquals(plcrash_async_thread_state_init(&ts, CPU_TYPE_ARM), PLCRASH_ESUCCESS, @"Failed to initialize thread state");
    STAssertEquals(ts.stack_direction, PLCRASH_ASYNC_THREAD_STACK_DIRECTION_DOWN, @"Incorrect stack direction");
    STAssertEquals(ts.greg_size, (size_t)4, @"Incorrect gpreg size");
#endif
}

/* Test plcrash_async_thread_state_ucontext_init() */
- (void) testThreadStateContextInit {
    plcrash_async_thread_state_t thr_state;
    _STRUCT_MCONTEXT mctx;

    memset(&mctx, 'A', sizeof(mctx));
    
    plcrash_async_thread_state_mcontext_init(&thr_state, &mctx);
    
    /* Verify that all registers are marked as available */
    size_t regcount = plcrash_async_thread_state_get_reg_count(&thr_state);
    STAssertTrue(__builtin_popcount(thr_state.valid_regs) >= regcount, @"Incorrect number of 1 bits");
    for (int i = 0; i < plcrash_async_thread_state_get_reg_count(&thr_state); i++) {
        STAssertTrue(plcrash_async_thread_state_has_reg(&thr_state, i), @"Register should be marked as set");
    }
    
#if defined(PLCRASH_ASYNC_THREAD_ARM_SUPPORT)
    STAssertTrue(memcmp(&thr_state.arm_state.thread, &mctx.__ss, sizeof(thr_state.arm_state.thread)) == 0, @"Incorrectly copied");
    
#elif defined(PLCRASH_ASYNC_THREAD_X86_SUPPORT) && defined(__LP64__)
    STAssertEquals(thr_state.x86_state.thread.tsh.count, (int)x86_THREAD_STATE64_COUNT, @"Incorrect thread state count for a 64-bit system");
    STAssertEquals(thr_state.x86_state.thread.tsh.flavor, (int)x86_THREAD_STATE64, @"Incorrect thread state flavor for a 64-bit system");
    STAssertTrue(memcmp(&thr_state.x86_state.thread.uts.ts64, &mctx.__ss, sizeof(thr_state.x86_state.thread.uts.ts64)) == 0, @"Incorrectly copied");
    
    STAssertEquals(thr_state.x86_state.exception.esh.count, (int) x86_EXCEPTION_STATE64_COUNT, @"Incorrect thread state count for a 64-bit system");
    STAssertEquals(thr_state.x86_state.exception.esh.flavor, (int) x86_EXCEPTION_STATE64, @"Incorrect thread state flavor for a 64-bit system");
    STAssertTrue(memcmp(&thr_state.x86_state.exception.ues.es64, &mctx.__es, sizeof(thr_state.x86_state.exception.ues.es64)) == 0, @"Incorrectly copied");
#elif defined(PLCRASH_ASYNC_THREAD_X86_SUPPORT)
    STAssertEquals(thr_state.x86_state.thread.tsh.count, (int)x86_THREAD_STATE32_COUNT, @"Incorrect thread state count for a 32-bit system");
    STAssertEquals(thr_state.x86_state.thread.tsh.flavor, (int)x86_THREAD_STATE32, @"Incorrect thread state flavor for a 32-bit system");
    STAssertTrue(memcmp(&thr_state.x86_state.thread.uts.ts32, &mctx.__ss, sizeof(thr_state.x86_state.thread.uts.ts32)) == 0, @"Incorrectly copied");
    
    STAssertEquals(thr_state.x86_state.exception.esh.count, (int)x86_EXCEPTION_STATE32_COUNT, @"Incorrect thread state count for a 32-bit system");
    STAssertEquals(thr_state.x86_state.exception.esh.flavor, (int)x86_EXCEPTION_STATE32, @"Incorrect thread state flavor for a 32-bit system");
    STAssertTrue(memcmp(&thr_state.x86_state.exception.ues.es32, &mctx.__es, sizeof(thr_state.x86_state.exception.ues.es32)) == 0, @"Incorrectly copied");
#else
#error Add platform support
#endif
}

/* Test plframe_thread_state_thread_init() */
- (void) testThreadStateThreadInit {
    plcrash_async_thread_state_t thr_state;
    mach_msg_type_number_t state_count;
    thread_t thr;
    
    /* Spawn a test thread */
    thr = pthread_mach_thread_np(_thr_args.thread);
    thread_suspend(thr);

    /* Fetch the thread state */
    STAssertEquals(plcrash_async_thread_state_mach_thread_init(&thr_state, thr), PLCRASH_ESUCCESS, @"Failed to initialize thread state");
    
    /* Verify that all registers are marked as available */
    size_t regcount = plcrash_async_thread_state_get_reg_count(&thr_state);
    STAssertTrue(__builtin_popcount(thr_state.valid_regs) >= regcount, @"Incorrect number of 1 bits");
    for (int i = 0; i < plcrash_async_thread_state_get_reg_count(&thr_state); i++) {
        STAssertTrue(plcrash_async_thread_state_has_reg(&thr_state, i), @"Register should be marked as set");
    }

    /* Test the results */
#if defined(PLCRASH_ASYNC_THREAD_ARM_SUPPORT)
    arm_thread_state_t local_thr_state;
    state_count = ARM_THREAD_STATE_COUNT;
    
    STAssertEquals(thread_get_state(thr, ARM_THREAD_STATE, (thread_state_t) &local_thr_state, &state_count), KERN_SUCCESS, @"Failed to fetch thread state");
    STAssertTrue(memcmp(&thr_state.arm_state.thread, &local_thr_state, sizeof(thr_state.arm_state.thread)) == 0, @"Incorrectly copied");
    
#elif defined(PLCRASH_ASYNC_THREAD_X86_SUPPORT) && defined(__LP64__)
    state_count = x86_THREAD_STATE64_COUNT;
    x86_thread_state64_t local_thr_state;
    STAssertEquals(thread_get_state(thr, x86_THREAD_STATE64, (thread_state_t) &local_thr_state, &state_count), KERN_SUCCESS, @"Failed to fetch thread state");
    STAssertTrue(memcmp(&thr_state.x86_state.thread.uts.ts64, &local_thr_state, sizeof(thr_state.x86_state.thread.uts.ts64)) == 0, @"Incorrectly copied");
    STAssertEquals(thr_state.x86_state.thread.tsh.count, (int)x86_THREAD_STATE64_COUNT, @"Incorrect thread state count for a 64-bit system");
    STAssertEquals(thr_state.x86_state.thread.tsh.flavor, (int)x86_THREAD_STATE64, @"Incorrect thread state flavor for a 64-bit system");
    
    state_count = x86_EXCEPTION_STATE64_COUNT;
    x86_exception_state64_t local_exc_state;
    STAssertEquals(thread_get_state(thr, x86_EXCEPTION_STATE64, (thread_state_t) &local_exc_state, &state_count), KERN_SUCCESS, @"Failed to fetch thread state");
    STAssertTrue(memcmp(&thr_state.x86_state.exception.ues.es64, &local_exc_state, sizeof(thr_state.x86_state.exception.ues.es64)) == 0, @"Incorrectly copied");
    STAssertEquals(thr_state.x86_state.exception.esh.count, (int) x86_EXCEPTION_STATE64_COUNT, @"Incorrect thread state count for a 64-bit system");
    STAssertEquals(thr_state.x86_state.exception.esh.flavor, (int) x86_EXCEPTION_STATE64, @"Incorrect thread state flavor for a 64-bit system");
    
#elif defined(PLCRASH_ASYNC_THREAD_X86_SUPPORT)
    state_count = x86_THREAD_STATE32_COUNT;
    x86_thread_state32_t local_thr_state;
    STAssertEquals(thread_get_state(thr, x86_THREAD_STATE32, (thread_state_t) &local_thr_state, &state_count), KERN_SUCCESS, @"Failed to fetch thread state");
    STAssertTrue(memcmp(&thr_state.x86_state.thread.uts.ts32, &local_thr_state, sizeof(thr_state.x86_state.thread.uts.ts32)) == 0, @"Incorrectly copied");
    STAssertEquals(thr_state.x86_state.thread.tsh.count, (int)x86_THREAD_STATE32_COUNT, @"Incorrect thread state count for a 64-bit system");
    STAssertEquals(thr_state.x86_state.thread.tsh.flavor, (int)x86_THREAD_STATE32, @"Incorrect thread state flavor for a 32-bit system");
    
    state_count = x86_EXCEPTION_STATE32_COUNT;
    x86_exception_state32_t local_exc_state;
    STAssertEquals(thread_get_state(thr, x86_EXCEPTION_STATE32, (thread_state_t) &local_exc_state, &state_count), KERN_SUCCESS, @"Failed to fetch thread state");
    STAssertTrue(memcmp(&thr_state.x86_state.exception.ues.es32, &local_exc_state, sizeof(thr_state.x86_state.exception.ues.es32)) == 0, @"Incorrectly copied");
    STAssertEquals(thr_state.x86_state.exception.esh.count, (int) x86_EXCEPTION_STATE32_COUNT, @"Incorrect thread state count for a 32-bit system");
    STAssertEquals(thr_state.x86_state.exception.esh.flavor, (int) x86_EXCEPTION_STATE32, @"Incorrect thread state flavor for a 32-bit system");
#else
#error Add platform support
#endif
    
    /* Verify the platform metadata */
#ifdef __LP64__
    STAssertEquals(plcrash_async_thread_state_get_greg_size(&thr_state), (size_t)8, @"Incorrect greg size");
#else
    STAssertEquals(plcrash_async_thread_state_get_greg_size(&thr_state), (size_t)4, @"Incorrect greg size");
#endif

#if defined(__arm__) || defined(__i386__) || defined(__x86_64__)
    // This is true on just about every modern platform
    STAssertEquals(plcrash_async_thread_state_get_stack_direction(&thr_state), PLCRASH_ASYNC_THREAD_STACK_DIRECTION_DOWN, @"Incorrect stack growth direction");
#else
#error Add platform support!
#endif

    /* Clean up */
    thread_resume(thr);
}

static uintptr_t getPC () {
    return (uintptr_t) __builtin_return_address(0);
}

static plcrash_error_t write_current_thread_callback (plcrash_async_thread_state_t *state, void *context) {
    plcrash_async_thread_state_t *result = context;
    plcrash_async_thread_state_copy(result, state);
    return PLCRASH_ESUCCESS;
}

/**
 * Test fetching the current thread's state
 */
- (void) testFetchCurrentThreadState {
    /* Write the crash report */
    plcrash_async_thread_state_t thr_state;
    plcrash_error_t ret = plcrash_async_thread_state_current(write_current_thread_callback, &thr_state);
    uintptr_t expectedPC = getPC();
    
    STAssertEquals(PLCRASH_ESUCCESS, ret, @"Crash log failed");
    
    /* Validate PC. This check is inexact, as otherwise we would need to carefully instrument the
     * call to plcrash_log_writer_write_curthread() in order to determine the exact PC value. */
    STAssertTrue(expectedPC - plcrash_async_thread_state_get_reg(&thr_state, PLCRASH_REG_IP) <= 20, @"PC value not within reasonable range");
    
    /* Fetch stack info for validation */
    uint8_t *stackaddr = pthread_get_stackaddr_np(pthread_self());
    size_t stacksize = pthread_get_stacksize_np(pthread_self());
    
    /* Verify that the stack pointer is sane */
    plcrash_greg_t sp = plcrash_async_thread_state_get_reg(&thr_state, PLCRASH_REG_SP);
    if (plcrash_async_thread_state_get_stack_direction(&thr_state) == PLCRASH_ASYNC_THREAD_STACK_DIRECTION_DOWN) {
        STAssertTrue((uint8_t *)sp < stackaddr && (uint8_t *) sp >= stackaddr-stacksize, @"Stack pointer outside of stack range");
    } else {
        STAssertTrue((uint8_t *)sp > stackaddr && (uint8_t *) sp < stackaddr+stacksize, @"Stack pointer outside of stack range");
    }
    
    /* Architecture-specific validations */
#if __arm__
    /* Validate LR */
    void *retaddr = __builtin_return_address(0);
    uintptr_t lr = plcrash_async_thread_state_get_reg(&thr_state, PLCRASH_ARM_LR);
    STAssertEquals(retaddr, (void *)lr, @"Incorrect lr: %p", (void *) lr);
#endif
}

- (void) testThreadStateCopy {
    plcrash_async_thread_state_t thr_state;
    thread_t thr;
    
    /* Spawn a test thread */
    thr = pthread_mach_thread_np(_thr_args.thread);
    thread_suspend(thr);
    
    /* Fetch the thread state */
    STAssertEquals(plcrash_async_thread_state_mach_thread_init(&thr_state, thr), PLCRASH_ESUCCESS, @"Failed to initialize thread state");
    
    /* Try a copy */
    plcrash_async_thread_state_t thr_copy;
    plcrash_async_thread_state_copy(&thr_copy, &thr_state);
    STAssertEquals(memcmp(&thr_copy, &thr_state, sizeof(thr_copy)), 0, @"Did not correctly copy thread state");
    
    /* Clean up */
    thread_resume(thr);
}

@end
