#!/bin/sh
# ----------------------------------------------------------------------------
# Licensed to the Apache Software Foundation (ASF) under one
# or more contributor license agreements.  See the NOTICE file
# distributed with this work for additional information
# regarding copyright ownership.  The ASF licenses this file
# to you under the Apache License, Version 2.0 (the
# "License"); you may not use this file except in compliance
# with the License.  You may obtain a copy of the License at
#
#    https://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing,
# software distributed under the License is distributed on an
# "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
# KIND, either express or implied.  See the License for the
# specific language governing permissions and limitations
# under the License.
# ----------------------------------------------------------------------------

# ----------------------------------------------------------------------------
# Apache Maven Wrapper startup script, version 3.3.2
# ----------------------------------------------------------------------------

# If JAVA_HOME is set, use it; else use java from PATH
if [ -n "$JAVA_HOME" ] ; then
  if [ -x "$JAVA_HOME/jre/sh/java" ] ; then
    JAVACMD="$JAVA_HOME/jre/sh/java"
  else
    JAVACMD="$JAVA_HOME/bin/java"
  fi
  if [ ! -x "$JAVACMD" ] ; then
    die "ERROR: JAVA_HOME is set to an invalid directory: $JAVA_HOME"
  fi
else
  JAVACMD="$( \
    unset CDPATH && \
    nohup sh -c 'command -v java' 2>/dev/null )"
  if [ -z "$JAVACMD" ] ; then
    die "ERROR: JAVA_HOME is not set and no 'java' command could be found in your PATH."
  fi
fi

# Use system Maven if available and wrapper jar not present
if command -v mvn >/dev/null 2>&1; then
  exec mvn "$@"
fi

die() {
  echo "$*" >&2
  exit 1
}

die "ERROR: Maven wrapper is not bootstrapped and 'mvn' not found in PATH."
