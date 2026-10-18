param(
    [string]$Dll = 'F:\project\lang\simple_language\project\cvm_sl_mysql_lib\x64\Debug\sl_mysql_lib.dll',
    [string]$Host_ = 'bj-cdb-mri5uaiu.sql.tencentcdb.com',
    [int]$Port = 22718,
    [string]$User = 'root',
    [string]$Password = 'Likecg00@123',
    [string]$Database = 'ry_net'
)

Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public class SLM {
  [DllImport("kernel32.dll", CharSet=CharSet.Unicode, SetLastError=true)]
  public static extern IntPtr LoadLibraryW(string lp);
  [DllImport("kernel32.dll", CharSet=CharSet.Ansi, SetLastError=true, ExactSpelling=true)]
  public static extern IntPtr GetProcAddress(IntPtr h, string name);
  [UnmanagedFunctionPointer(CallingConvention.Cdecl)] public delegate long P_Init();
  [UnmanagedFunctionPointer(CallingConvention.Cdecl)] public delegate int  P_Connect(long h,string host,string user,string pwd,string db,int port);
  [UnmanagedFunctionPointer(CallingConvention.Cdecl)] public delegate IntPtr P_Error(long h);
  [UnmanagedFunctionPointer(CallingConvention.Cdecl)] public delegate bool  P_Query(long h,string sql);
  [UnmanagedFunctionPointer(CallingConvention.Cdecl)] public delegate bool  P_SelectDb(long h,string db);
  [UnmanagedFunctionPointer(CallingConvention.Cdecl)] public delegate IntPtr P_Info();
  [UnmanagedFunctionPointer(CallingConvention.Cdecl)] public delegate void  P_Close(long h);
  public static T Bind<T>(string dll, string sym) where T : class {
    IntPtr h = LoadLibraryW(dll);
    if (h == IntPtr.Zero) throw new Exception("LoadLibrary failed: " + dll);
    IntPtr p = GetProcAddress(h, sym);
    if (p == IntPtr.Zero) throw new Exception("symbol not found: " + sym);
    return Marshal.GetDelegateForFunctionPointer(p, typeof(T)) as T;
  }
}
'@ -ErrorAction Stop

$A = [Runtime.InteropServices.Marshal]
$mi = [SLM].GetMethod('Bind')
function Bind([string]$sym, [type]$t) { $mi.MakeGenericMethod($t).Invoke($null, @($Dll, $sym)) }

try {
    $info     = Bind 'slm_client_info' ([SLM+P_Info])
    Write-Output ("clientInfo = " + $A::PtrToStringAnsi($info.Invoke()))

    $init     = Bind 'slm_init'     ([SLM+P_Init])
    $connect  = Bind 'slm_connect'  ([SLM+P_Connect])
    $err      = Bind 'slm_error'    ([SLM+P_Error])
    $query    = Bind 'slm_query'    ([SLM+P_Query])
    $selectDb = Bind 'slm_select_db'([SLM+P_SelectDb])
    $close    = Bind 'slm_close'    ([SLM+P_Close])

    $h = $init.Invoke()
    Write-Output ("init handle = " + $h)

    $ok = $connect.Invoke($h, $Host_, $User, $Password, $Database, $Port)
    Write-Output ("connect = " + $ok)
    if ($ok -eq 0) {
        Write-Output ("error = " + $A::PtrToStringAnsi($err.Invoke($h)))
        exit 1
    }

    $r = $query.Invoke($h, 'SELECT VERSION()')
    Write-Output ("query SELECT VERSION() = " + $r + " err=" + $A::PtrToStringAnsi($err.Invoke($h)))

    $r = $query.Invoke($h, 'CREATE DATABASE IF NOT EXISTS sl_mysql_test DEFAULT CHARSET utf8mb4')
    Write-Output ("create database = " + $r + " err=" + $A::PtrToStringAnsi($err.Invoke($h)))

    $r = $selectDb.Invoke($h, 'sl_mysql_test')
    Write-Output ("select db = " + $r)

    $r = $query.Invoke($h, 'CREATE TABLE IF NOT EXISTS t_smoke(id INT PRIMARY KEY AUTO_INCREMENT, name VARCHAR(64))')
    Write-Output ("create table = " + $r + " err=" + $A::PtrToStringAnsi($err.Invoke($h)))
}
catch {
    Write-Output ("EXCEPTION: " + $_.Exception.Message)
    exit 1
}
