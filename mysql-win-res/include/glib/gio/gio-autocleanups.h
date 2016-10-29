﻿#pragma execution_character_set("utf-8")

/*
 * Copyright © 2015 Canonical Limited
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Lesser General Public
 * License as published by the Free Software Foundation; either
 * version 2 of the licence, or (at your option) any later version.
 *
 * This library is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
 * Lesser General Public License for more details.
 *
 * You should have received a copy of the GNU Lesser General Public
 * License along with this library; if not, see <http://www.gnu.org/licenses/>.
 *
 * Author: Ryan Lortie <desrt@desrt.ca>
 */

#if !defined (__GIO_GIO_H_INSIDE__) && !defined (GIO_COMPILATION)
#error "Only <gio/gio.h> can be included directly."
#endif

G_DEFINE_AUTOPTR_CLEANUP_FUNC(GAction, g_object_unref)
G_DEFINE_AUTOPTR_CLEANUP_FUNC(GActionMap, g_object_unref)
G_DEFINE_AUTOPTR_CLEANUP_FUNC(GAppInfo, g_object_unref)
G_DEFINE_AUTOPTR_CLEANUP_FUNC(GAppLaunchContext, g_object_unref)
G_DEFINE_AUTOPTR_CLEANUP_FUNC(GAppInfoMonitor, g_object_unref)
G_DEFINE_AUTOPTR_CLEANUP_FUNC(GApplicationCommandLine, g_object_unref)
G_DEFINE_AUTOPTR_CLEANUP_FUNC(GApplication, g_object_unref)
G_DEFINE_AUTOPTR_CLEANUP_FUNC(GAsyncInitable, g_object_unref)
G_DEFINE_AUTOPTR_CLEANUP_FUNC(GAsyncResult, g_object_unref)
G_DEFINE_AUTOPTR_CLEANUP_FUNC(GBufferedInputStream, g_object_unref)
G_DEFINE_AUTOPTR_CLEANUP_FUNC(GBufferedOutputStream, g_object_unref)
G_DEFINE_AUTOPTR_CLEANUP_FUNC(GBytesIcon, g_object_unref)
G_DEFINE_AUTOPTR_CLEANUP_FUNC(GCancellable, g_object_unref)
G_DEFINE_AUTOPTR_CLEANUP_FUNC(GCharsetConverter, g_object_unref)
G_DEFINE_AUTOPTR_CLEANUP_FUNC(GConverter, g_object_unref)
G_DEFINE_AUTOPTR_CLEANUP_FUNC(GConverterInputStream, g_object_unref)
G_DEFINE_AUTOPTR_CLEANUP_FUNC(GConverterOutputStream, g_object_unref)
G_DEFINE_AUTOPTR_CLEANUP_FUNC(GCredentials, g_object_unref)
G_DEFINE_AUTOPTR_CLEANUP_FUNC(GDatagramBased, g_object_unref)
G_DEFINE_AUTOPTR_CLEANUP_FUNC(GDataInputStream, g_object_unref)
G_DEFINE_AUTOPTR_CLEANUP_FUNC(GDataOutputStream, g_object_unref)
G_DEFINE_AUTOPTR_CLEANUP_FUNC(GDBusActionGroup, g_object_unref)
G_DEFINE_AUTOPTR_CLEANUP_FUNC(GDBusAuthObserver, g_object_unref)
G_DEFINE_AUTOPTR_CLEANUP_FUNC(GDBusConnection, g_object_unref)
G_DEFINE_AUTOPTR_CLEANUP_FUNC(GDBusInterface, g_object_unref)
G_DEFINE_AUTOPTR_CLEANUP_FUNC(GDBusInterfaceSkeleton, g_object_unref)
G_DEFINE_AUTOPTR_CLEANUP_FUNC(GDBusMenuModel, g_object_unref)
G_DEFINE_AUTOPTR_CLEANUP_FUNC(GDBusMessage, g_object_unref)
G_DEFINE_AUTOPTR_CLEANUP_FUNC(GDBusMethodInvocation, g_object_unref)
G_DEFINE_AUTOPTR_CLEANUP_FUNC(GDBusNodeInfo, g_dbus_node_info_unref)
G_DEFINE_AUTOPTR_CLEANUP_FUNC(GDBusObject, g_object_unref)
G_DEFINE_AUTOPTR_CLEANUP_FUNC(GDBusObjectManagerClient, g_object_unref)
G_DEFINE_AUTOPTR_CLEANUP_FUNC(GDBusObjectManager, g_object_unref)
G_DEFINE_AUTOPTR_CLEANUP_FUNC(GDBusObjectManagerServer, g_object_unref)
G_DEFINE_AUTOPTR_CLEANUP_FUNC(GDBusObjectProxy, g_object_unref)
G_DEFINE_AUTOPTR_CLEANUP_FUNC(GDBusObjectSkeleton, g_object_unref)
G_DEFINE_AUTOPTR_CLEANUP_FUNC(GDBusProxy, g_object_unref)
G_DEFINE_AUTOPTR_CLEANUP_FUNC(GDBusServer, g_object_unref)
G_DEFINE_AUTOPTR_CLEANUP_FUNC(GDrive, g_object_unref)
G_DEFINE_AUTOPTR_CLEANUP_FUNC(GEmblemedIcon, g_object_unref)
G_DEFINE_AUTOPTR_CLEANUP_FUNC(GEmblem, g_object_unref)
G_DEFINE_AUTOPTR_CLEANUP_FUNC(GFileEnumerator, g_object_unref)
G_DEFINE_AUTOPTR_CLEANUP_FUNC(GFile, g_object_unref)
G_DEFINE_AUTOPTR_CLEANUP_FUNC(GFileAttributeInfoList, g_file_attribute_info_list_unref)
G_DEFINE_AUTOPTR_CLEANUP_FUNC(GFileIcon, g_object_unref)
G_DEFINE_AUTOPTR_CLEANUP_FUNC(GFileInfo, g_object_unref)
G_DEFINE_AUTOPTR_CLEANUP_FUNC(GFileInputStream, g_object_unref)
G_DEFINE_AUTOPTR_CLEANUP_FUNC(GFileIOStream, g_object_unref)
G_DEFINE_AUTOPTR_CLEANUP_FUNC(GFileMonitor, g_object_unref)
G_DEFINE_AUTOPTR_CLEANUP_FUNC(GFilenameCompleter, g_object_unref)
G_DEFINE_AUTOPTR_CLEANUP_FUNC(GFileOutputStream, g_object_unref)
G_DEFINE_AUTOPTR_CLEANUP_FUNC(GFilterInputStream, g_object_unref)
G_DEFINE_AUTOPTR_CLEANUP_FUNC(GFilterOutputStream, g_object_unref)
G_DEFINE_AUTOPTR_CLEANUP_FUNC(GIcon, g_object_unref)
G_DEFINE_AUTOPTR_CLEANUP_FUNC(GInetAddress, g_object_unref)
G_DEFINE_AUTOPTR_CLEANUP_FUNC(GInetAddressMask, g_object_unref)
G_DEFINE_AUTOPTR_CLEANUP_FUNC(GInetSocketAddress, g_object_unref)
G_DEFINE_AUTOPTR_CLEANUP_FUNC(GInitable, g_object_unref)
G_DEFINE_AUTOPTR_CLEANUP_FUNC(GInputStream, g_object_unref)
G_DEFINE_AUTOPTR_CLEANUP_FUNC(GIOModule, g_object_unref)
G_DEFINE_AUTOPTR_CLEANUP_FUNC(GIOStream, g_object_unref)
G_DEFINE_AUTOPTR_CLEANUP_FUNC(GLoadableIcon, g_object_unref)
G_DEFINE_AUTOPTR_CLEANUP_FUNC(GMemoryInputStream, g_object_unref)
G_DEFINE_AUTOPTR_CLEANUP_FUNC(GMemoryOutputStream, g_object_unref)
G_DEFINE_AUTOPTR_CLEANUP_FUNC(GMenu, g_object_unref)
G_DEFINE_AUTOPTR_CLEANUP_FUNC(GMenuItem, g_object_unref)
G_DEFINE_AUTOPTR_CLEANUP_FUNC(GMenuModel, g_object_unref)
G_DEFINE_AUTOPTR_CLEANUP_FUNC(GMenuAttributeIter, g_object_unref)
G_DEFINE_AUTOPTR_CLEANUP_FUNC(GMenuLinkIter, g_object_unref)
G_DEFINE_AUTOPTR_CLEANUP_FUNC(GMount, g_object_unref)
G_DEFINE_AUTOPTR_CLEANUP_FUNC(GMountOperation, g_object_unref)
G_DEFINE_AUTOPTR_CLEANUP_FUNC(GNativeVolumeMonitor, g_object_unref)
G_DEFINE_AUTOPTR_CLEANUP_FUNC(GNetworkAddress, g_object_unref)
G_DEFINE_AUTOPTR_CLEANUP_FUNC(GNetworkMonitor, g_object_unref)
G_DEFINE_AUTOPTR_CLEANUP_FUNC(GNetworkService, g_object_unref)
G_DEFINE_AUTOPTR_CLEANUP_FUNC(GNotification, g_object_unref)
G_DEFINE_AUTOPTR_CLEANUP_FUNC(GOutputStream, g_object_unref)
G_DEFINE_AUTOPTR_CLEANUP_FUNC(GPermission, g_object_unref)
G_DEFINE_AUTOPTR_CLEANUP_FUNC(GPollableInputStream, g_object_unref)
G_DEFINE_AUTOPTR_CLEANUP_FUNC(GPollableOutputStream, g_object_unref)
G_DEFINE_AUTOPTR_CLEANUP_FUNC(GPropertyAction, g_object_unref)
G_DEFINE_AUTOPTR_CLEANUP_FUNC(GProxyAddressEnumerator, g_object_unref)
G_DEFINE_AUTOPTR_CLEANUP_FUNC(GProxyAddress, g_object_unref)
G_DEFINE_AUTOPTR_CLEANUP_FUNC(GProxy, g_object_unref)
G_DEFINE_AUTOPTR_CLEANUP_FUNC(GProxyResolver, g_object_unref)
G_DEFINE_AUTOPTR_CLEANUP_FUNC(GRemoteActionGroup, g_object_unref)
G_DEFINE_AUTOPTR_CLEANUP_FUNC(GResolver, g_object_unref)
G_DEFINE_AUTOPTR_CLEANUP_FUNC(GSeekable, g_object_unref)
G_DEFINE_AUTOPTR_CLEANUP_FUNC(GSettingsBackend, g_object_unref)
G_DEFINE_AUTOPTR_CLEANUP_FUNC(GSettingsSchema, g_settings_schema_unref)
G_DEFINE_AUTOPTR_CLEANUP_FUNC(GSettings, g_object_unref)
G_DEFINE_AUTOPTR_CLEANUP_FUNC(GSimpleActionGroup, g_object_unref)
G_DEFINE_AUTOPTR_CLEANUP_FUNC(GSimpleAction, g_object_unref)
G_DEFINE_AUTOPTR_CLEANUP_FUNC(GSimpleAsyncResult, g_object_unref)
G_DEFINE_AUTOPTR_CLEANUP_FUNC(GSimplePermission, g_object_unref)
G_DEFINE_AUTOPTR_CLEANUP_FUNC(GSimpleProxyResolver, g_object_unref)
G_DEFINE_AUTOPTR_CLEANUP_FUNC(GSocketAddressEnumerator, g_object_unref)
G_DEFINE_AUTOPTR_CLEANUP_FUNC(GSocketAddress, g_object_unref)
G_DEFINE_AUTOPTR_CLEANUP_FUNC(GSocketClient, g_object_unref)
G_DEFINE_AUTOPTR_CLEANUP_FUNC(GSocketConnectable, g_object_unref)
G_DEFINE_AUTOPTR_CLEANUP_FUNC(GSocketConnection, g_object_unref)
G_DEFINE_AUTOPTR_CLEANUP_FUNC(GSocketControlMessage, g_object_unref)
G_DEFINE_AUTOPTR_CLEANUP_FUNC(GSocket, g_object_unref)
G_DEFINE_AUTOPTR_CLEANUP_FUNC(GSocketListener, g_object_unref)
G_DEFINE_AUTOPTR_CLEANUP_FUNC(GSocketService, g_object_unref)
G_DEFINE_AUTOPTR_CLEANUP_FUNC(GSubprocess, g_object_unref)
G_DEFINE_AUTOPTR_CLEANUP_FUNC(GSubprocessLauncher, g_object_unref)
G_DEFINE_AUTOPTR_CLEANUP_FUNC(GTask, g_object_unref)
G_DEFINE_AUTOPTR_CLEANUP_FUNC(GTcpConnection, g_object_unref)
G_DEFINE_AUTOPTR_CLEANUP_FUNC(GTcpWrapperConnection, g_object_unref)
G_DEFINE_AUTOPTR_CLEANUP_FUNC(GTestDBus, g_object_unref)
G_DEFINE_AUTOPTR_CLEANUP_FUNC(GThemedIcon, g_object_unref)
G_DEFINE_AUTOPTR_CLEANUP_FUNC(GThreadedSocketService, g_object_unref)
G_DEFINE_AUTOPTR_CLEANUP_FUNC(GTlsBackend, g_object_unref)
G_DEFINE_AUTOPTR_CLEANUP_FUNC(GTlsCertificate, g_object_unref)
G_DEFINE_AUTOPTR_CLEANUP_FUNC(GTlsClientConnection, g_object_unref)
G_DEFINE_AUTOPTR_CLEANUP_FUNC(GTlsConnection, g_object_unref)
G_DEFINE_AUTOPTR_CLEANUP_FUNC(GTlsDatabase, g_object_unref)
G_DEFINE_AUTOPTR_CLEANUP_FUNC(GTlsFileDatabase, g_object_unref)
G_DEFINE_AUTOPTR_CLEANUP_FUNC(GTlsInteraction, g_object_unref)
G_DEFINE_AUTOPTR_CLEANUP_FUNC(GTlsPassword, g_object_unref)
G_DEFINE_AUTOPTR_CLEANUP_FUNC(GTlsServerConnection, g_object_unref)
G_DEFINE_AUTOPTR_CLEANUP_FUNC(GVfs, g_object_unref)
G_DEFINE_AUTOPTR_CLEANUP_FUNC(GVolume, g_object_unref)
G_DEFINE_AUTOPTR_CLEANUP_FUNC(GVolumeMonitor, g_object_unref)
G_DEFINE_AUTOPTR_CLEANUP_FUNC(GZlibCompressor, g_object_unref)
G_DEFINE_AUTOPTR_CLEANUP_FUNC(GZlibDecompressor, g_object_unref)
