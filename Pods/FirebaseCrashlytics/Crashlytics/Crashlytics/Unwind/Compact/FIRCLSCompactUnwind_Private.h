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

#include "Crashlytics/Crashlytics/Unwind/Compact/FIRCLSCompactUnwind.h"
#pragma pack(push, 1)
#include <mach-o/compact_unwind_encoding.h>
#pragma pack(pop)

bool FIRCLSCompactUnwindLookup(FIRCLSCompactUnwindContext* context,
                               uintptr_t pc,
                               FIRCLSCompactUnwindResult* result);

bool FIRCLSCompactUnwindComputeRegisters(FIRCLSCompactUnwindContext* context,
                                         FIRCLSCompactUnwindResult* result,
                                         FIRCLSThreadContext* registers);
