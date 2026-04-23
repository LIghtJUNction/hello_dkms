/*
 * Copyright (c) 2026 lightjunction
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 */

/*
 * Convention: pr_fmt must be defined BEFORE any includes.
 * KBUILD_MODNAME is automatically defined by the build system.
 */
#define pr_fmt(fmt) KBUILD_MODNAME ": " fmt

#include <linux/init.h>   /* For __init and __exit macros */
#include <linux/kernel.h> /* Contains types, macros, functions for the kernel */
#include <linux/module.h> /* Core header for loading modules */
#include <linux/version.h> /* For LINUX_VERSION_CODE macros */

/*
 * Internal Kernel API Checklist:
 * 1. __init: Marks the function for the initialization phase. Memory is freed
 * after boot/load.
 * 2. __exit: Marks the function for cleanup. Discarded if the module is
 * built-in.
 * 3. static: Prevents symbol pollution in the global kernel namespace.
 * 4. (void): Explicitly state no arguments, as per C standards in kernel.
 */

#if LINUX_VERSION_CODE >= KERNEL_VERSION(7, 0, 0)
/*
 * Specific logic for Kernel 7.0.0+
 * CachyOS BORE/LTO often enforces strict objtool checks here.
 */
#endif

/**
 * hello_dkms_init - Module entry point
 * Return: 0 on success, negative error code on failure (e.g., -ENOMEM)
 */
static int __init hello_dkms_init(void) {
	/* Modern kernel practice: use pr_* instead of printk(KERN_*) */
	pr_info("Hello world!\n");

	return 0;
}

/**
 * hello_dkms_exit - Module exit point
 */
static void __exit hello_dkms_exit(void) {
	pr_info("Goodbye world!\n");
}

module_init(hello_dkms_init);
module_exit(hello_dkms_exit);

#include "version.h"
/*
 * Metadata Conventions:
 * 1. MODULE_LICENSE: Required to avoid "Tainted Kernel" warning. "GPL" means
 * GPL v2 or later.
 * 2. MODULE_AUTHOR: Use Name <email@example.com> format.
 * 3. MODULE_ALIAS: Allows auto-loading via different names.
 */
#ifndef MODULE_VERSION_STRING
#define MODULE_VERSION_STRING "unspecified"
#endif
MODULE_AUTHOR("lightjunction <lightjunction.me@gmail.com>");
MODULE_DESCRIPTION("Standard Hello World DKMS module");
MODULE_VERSION(MODULE_VERSION_STRING);
MODULE_LICENSE("GPL");
MODULE_ALIAS("hello_world");

MODULE_SOFTDEP("");
MODULE_WEAKDEP("");

#if LINUX_VERSION_CODE >= KERNEL_VERSION(6, 13, 0)
// 6.13
MODULE_IMPORT_NS("xxx");
#else
// old
MODULE_IMPORT_NS(xxx);
#endif

/*
 * Enumerated Kernel Macros for reference:
 * - MODULE_SOFTDEP: "pre: module_a post: module_b" (Dependency hints)
 * - MODULE_IMPORT_NS: Import specific symbol namespaces (required for some 5.4+
 * APIs)
 * - EXPORT_SYMBOL: Make functions available to other modules (not needed here)
 */
