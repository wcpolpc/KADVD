#!/usr/bin/env python
#
# Copyright 2007 Google Inc.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#




"""Relational database API stub that uses the MySQLdb DB-API library.

Also see the rdbms module.
"""







import logging
import os

_POTENTIAL_SOCKET_LOCATIONS = (
    '/tmp/mysql.sock',
    '/var/run/mysqld/mysqld.sock',
    '/var/lib/mysql/mysql.sock',
    '/var/run/mysql/mysql.sock',
    '/var/mysql/mysql.sock',
    )


_connect_kwargs = {}

def SetConnectKwargs(**kwargs):
  """Sets the keyword args (host, user, etc) to pass to MySQLdb.connect()."""

  global _connect_kwargs
  _connect_kwargs = dict(kwargs)


def FindUnixSocket():
  """Find the Unix socket for MySQL by scanning some known locations.

  Returns:
    If found, the path to the Unix socket, otherwise, None.
  """
  for path in _POTENTIAL_SOCKET_LOCATIONS:
    if os.path.exists(path):
      return path


try:
  import google
  import MySQLdb

  from MySQLdb import *


  def connect(instance=None, database=None, **kwargs):
    merged_kwargs = _connect_kwargs.copy()
    if database:
      merged_kwargs['db'] = database
    merged_kwargs.update(kwargs)
    host = merged_kwargs.get('host')
    if ((not host or host == 'localhost') and
        not merged_kwargs.get('unix_socket')):
      socket = FindUnixSocket()
      if socket:
        merged_kwargs['unix_socket'] = socket
      else:
        logging.warning(
            'Unable to find MySQL socket file.  Use --mysql_socket to '
            'specify its location manually.')
    logging.info('Connecting to MySQL with kwargs %r', merged_kwargs)
    return MySQLdb.connect(**merged_kwargs)

except ImportError:
  logging.warning('The rdbms API is not available because the MySQLdb '
                  'library could not be loaded.')


  def connect(instance=None, database=None):
    raise NotImplementedError(
        'Unable to find the MySQLdb library. Please see the SDK '
        'documentation for installation instructions.')


def set_instance(instance):
  logging.info('set_instance() is a noop in dev_appserver.')
