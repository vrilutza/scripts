/* SPDX-License-Identifier: GPL-2.0 */
/*
 * Stub trace header for out-of-tree DKMS build of applespi.
 * Provides no-op inline functions in place of real kernel tracepoints,
 * avoiding TRACE_INCLUDE_PATH resolution issues in out-of-tree builds.
 */

#ifndef _APPLESPI_TRACE_H_
#define _APPLESPI_TRACE_H_

#include <linux/types.h>
#include "applespi.h"

/* Inline no-op stubs — used as function pointers in applespi_get_trace_fun() */
static inline void trace_applespi_tp_ini_cmd(enum applespi_evt_type a,
	enum applespi_pkt_type b, u8 *c, size_t d) {}
static inline void trace_applespi_backlight_cmd(enum applespi_evt_type a,
	enum applespi_pkt_type b, u8 *c, size_t d) {}
static inline void trace_applespi_caps_lock_cmd(enum applespi_evt_type a,
	enum applespi_pkt_type b, u8 *c, size_t d) {}
static inline void trace_applespi_keyboard_data(enum applespi_evt_type a,
	enum applespi_pkt_type b, u8 *c, size_t d) {}
static inline void trace_applespi_touchpad_data(enum applespi_evt_type a,
	enum applespi_pkt_type b, u8 *c, size_t d) {}
static inline void trace_applespi_unknown_data(enum applespi_evt_type a,
	enum applespi_pkt_type b, u8 *c, size_t d) {}

/* Macros for calls with different signatures */
#define trace_applespi_bad_crc(...)		do {} while (0)
#define trace_applespi_irq_received(...)	do {} while (0)

#endif /* _APPLESPI_TRACE_H_ */
