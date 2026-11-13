# RegistryTest - Environment.registry content query test.
#
# Design doc PLATFORM_CAPABILITY_DESIGN.md §13.2 (registry class):
#   Environment.registry  exists / valueExists / getString / getInt /
#                         subKeyNames / valueNames
#
# Two branches (same verdict style as PlatformSixTest):
#   Windows  - real-key checks against HKLM\SOFTWARE\Microsoft\
#              Windows NT\CurrentVersion (present on every desktop
#              Windows since NT 4): ProductName (REG_SZ),
#              CurrentMajorVersionNumber (REG_DWORD, Win10+), plus
#              soft-fail checks against bogus keys/values.
#   Other    - the whole family must soft-fail: exists -> false,
#              getString -> "", getInt -> 0, names -> empty array.
# Note: SystemRegistry* dispatch is CVM-only (same as PlatformLibTest).

RegistryTest
{
    # 统一断言辅助：cond 为 true 打印 OK，否则打印 FAIL
    static check( string name, bool cond )
    {
        if cond
        {
            SystemPrintln( "[RegistryTest] " + name + " : OK" )
        }
        else
        {
            SystemPrintln( "[RegistryTest] " + name + " : FAIL" )
        }
    }

    # 观测：打印原值（不断言），供人工 / exe 直跑脚本核对
    static observeS( string name, string val )
    {
        SystemPrintln( "[RegistryTest] " + name + " : " + val )
    }

    # 简易子串判断（BaseTest 无字符串 contains 工具，逐字符扫描）
    static bool containsText( string s, string needle )
    {
        Int32 n = SystemStringLength( s )
        Int32 m = SystemStringLength( needle )
        Int32 i = 0
        while i + m <= n
        {
            bool ok = true
            Int32 j = 0
            while j < m
            {
                if SystemStringCharCodeAt( s, i + j ) != SystemStringCharCodeAt( needle, j )
                {
                    ok = false
                }
                j = j + 1
            }
            if ok
            {
                ret true
            }
            i = i + 1
        }
        ret false
    }

    static fun()
    {
        SystemPrintln( "========== RegistryTest (start) ==========" )

        nt = "SOFTWARE\\Microsoft\\Windows NT\\CurrentVersion"
        bogusKey = "SOFTWARE\\SlangNoSuchKey"
        bogusVal = "SlangNoSuchValue"

        if ( Environment.current.os == Environment.Platform.os.window )
        {
            SystemPrintln( "--- Windows branch (real key: HKLM " + nt + ") ---" )

            # 1. key existence
            check( "exists(HKLM, CurrentVersion)", Environment.registry.exists( "HKLM", nt ) )
            check( "exists lowercase root", Environment.registry.exists( "hklm", nt ) )
            check( "exists full root name", Environment.registry.exists( "HKEY_LOCAL_MACHINE", nt ) )
            check( "exists(HKCU, SOFTWARE)", Environment.registry.exists( "HKCU", "SOFTWARE" ) )
            check( "exists bogus key == false", Environment.registry.exists( "HKLM", bogusKey ) == false )
            check( "exists unknown root == false", Environment.registry.exists( "ZZZZ", "SOFTWARE" ) == false )

            # 2. value existence
            check( "valueExists(ProductName)", Environment.registry.valueExists( "HKLM", nt, "ProductName" ) )
            check( "valueExists bogus name == false", Environment.registry.valueExists( "HKLM", nt, bogusVal ) == false )
            check( "valueExists on bogus key == false", Environment.registry.valueExists( "HKLM", bogusKey, "ProductName" ) == false )

            # 3. typed reads
            productName = Environment.registry.getString( "HKLM", nt, "ProductName" )
            check( "getString(ProductName) non-empty", SystemStringLength( productName ) > 0 )
            check( "getString(ProductName) contains Windows", containsText( productName, "Windows" ) )
            major = Environment.registry.getInt( "HKLM", nt, "CurrentMajorVersionNumber" )
            check( "getInt(CurrentMajorVersionNumber) >= 10", major >= 10 )
            check( "getString(REG_DWORD value) == empty",
                Environment.registry.getString( "HKLM", nt, "CurrentMajorVersionNumber" ) == "" )
            check( "getInt(REG_SZ value) == 0",
                Environment.registry.getInt( "HKLM", nt, "ProductName" ) == 0 )

            # 4. soft-fail reads
            check( "getString bogus value == empty", Environment.registry.getString( "HKLM", nt, bogusVal ) == "" )
            check( "getString bogus key == empty", Environment.registry.getString( "HKLM", bogusKey, "ProductName" ) == "" )
            check( "getInt bogus value == 0", Environment.registry.getInt( "HKLM", nt, bogusVal ) == 0 )

            # 5. enumeration
            subKeys = Environment.registry.subKeyNames( "HKLM", "SOFTWARE" )
            check( "subKeyNames(SOFTWARE) non-empty", subKeys.length > 0 )
            check( "subKeyNames bogus key empty", Environment.registry.subKeyNames( "HKLM", bogusKey ).length == 0 )
            valNames = Environment.registry.valueNames( "HKLM", nt )
            check( "valueNames(CurrentVersion) non-empty", valNames.length > 0 )
            check( "valueNames bogus key empty", Environment.registry.valueNames( "HKLM", bogusKey ).length == 0 )

            found = false
            Int32 i = 0
            while i < valNames.length
            {
                if valNames[i] == "ProductName"
                {
                    found = true
                }
                i = i + 1
            }
            check( "valueNames contains ProductName", found )

            # observations (machine-dependent)
            observeS( "getString(ProductName)", productName )
            observeS( "getInt(CurrentMajorVersionNumber)", major.toString() )
            observeS( "subKeyNames(SOFTWARE).length", subKeys.length.toString() )
            observeS( "subKeyNames(SOFTWARE)[0]", subKeys[0] )
            observeS( "valueNames(CurrentVersion).length", valNames.length.toString() )
        }
        else
        {
            SystemPrintln( "--- Non-Windows branch (whole family soft-fails) ---" )

            check( "exists == false", Environment.registry.exists( "HKLM", "SOFTWARE" ) == false )
            check( "valueExists == false", Environment.registry.valueExists( "HKLM", "SOFTWARE", "x" ) == false )
            check( "getString == empty", Environment.registry.getString( "HKLM", "SOFTWARE", "x" ) == "" )
            check( "getInt == 0", Environment.registry.getInt( "HKLM", "SOFTWARE", "x" ) == 0 )
            check( "subKeyNames empty", Environment.registry.subKeyNames( "HKLM", "SOFTWARE" ).length == 0 )
            check( "valueNames empty", Environment.registry.valueNames( "HKLM", "SOFTWARE" ).length == 0 )
        }

        SystemPrintln( "========== RegistryTest (end) ==========" )
    }
}
