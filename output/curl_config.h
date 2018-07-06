#if defined(_WIN32)
#  include "curl_config_winapi.h"
#elif defined(__linux__)
#  if defined(__x86_64__)
#    include "curl_config_linux_x86_64.h"
#  elif defined(__i386__)
#    include "curl_config_linux_i686.h"
#  elif defined(__aarch64__)
#    include <curl_config_linux_aarch64.h>
#  elif defined(__arm__)
#    include <curl_config_linux_arm.h>
#  else
#    error "Unknown linux arch."
#  endif
#elif defined(__APPLE__)
#  include "curl_config_macosx.h"
#else
#  error "Unknown platform."
#endif
