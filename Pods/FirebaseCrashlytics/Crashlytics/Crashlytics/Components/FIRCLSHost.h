// Copyright 2019 Google
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//      http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

#pragma once

#include <mach/vm_types.h>
#include <sys/cdefs.h>

#include "Crashlytics/Crashlytics/Helpers/FIRCLSFile.h"

typedef struct {
  const char* documentDirectoryPath;
  vm_size_t pageSize;
} FIRCLSHostReadOnlyContext;

__BEGIN_DECLS

void FIRCLSHostInitialize(FIRCLSHostReadOnlyContext* roContext);

vm_size_t FIRCLSHostGetPageSize(void);

bool FIRCLSHostRecord(FIRCLSFile* file);

void FIRCLSHostWriteDiskUsage(FIRCLSFile* file);

__END_DECLS
