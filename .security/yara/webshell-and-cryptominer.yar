rule Suspicious_Webshell_Patterns {
  meta:
    description = "Detect common webshell execution patterns"
    author = "cicd-templates"
  strings:
    $php_exec = /<\?php[^\n]*\b(eval|assert|system|shell_exec|passthru|exec)\s*\(/ nocase
    $php_b64 = /base64_decode\s*\(/ nocase
    $jsp_exec = /Runtime\.getRuntime\(\)\.exec\s*\(/ nocase
    $asp_cmd = /cmd\.exe\s*\/c|powershell\.exe\s+/ nocase
  condition:
    any of them
}

rule Suspicious_Cryptominer_Patterns {
  meta:
    description = "Detect common cryptominer artifacts and pool usage"
    author = "cicd-templates"
  strings:
    $xmrig = "xmrig" nocase
    $minerd = "minerd" nocase
    $cpuminer = "cpuminer" nocase
    $stratum = /stratum\+tcp:\/\// nocase
    $miner_fetch = /(curl|wget)[^\n]{0,200}(xmrig|minerd|cpuminer)/ nocase
  condition:
    any of them
}
