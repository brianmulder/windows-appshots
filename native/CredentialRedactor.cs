using System;
using System.Collections.Generic;
using System.Text.RegularExpressions;

namespace WindowsAppshots
{
    internal sealed class CredentialRedactionException : Exception
    {
        internal CredentialRedactionException(string message) : base(message) { }
        internal CredentialRedactionException(string message, Exception inner) : base(message, inner) { }
    }

    internal sealed class CredentialRedactionReceipt
    {
        public string Policy = "credentials-v1";
        public bool Succeeded;
        public Dictionary<string, int> ReplacementCounts = new Dictionary<string, int>();
        public bool SemanticArtifactsSanitized = true;
        public bool RawMatchesPersisted;
        public bool VisualRedacted;
    }

    internal sealed class CredentialRedactor
    {
        private const string PrivateKeyClass = "PRIVATE_KEY";
        private const string AuthorizationClass = "AUTHORIZATION";
        private const string SessionCookieClass = "SESSION_COOKIE";
        private const string ConnectionSecretClass = "CONNECTION_SECRET";
        private const string ProviderTokenClass = "PROVIDER_TOKEN";
        private const string LabelledSecretClass = "LABELLED_SECRET";
        private const string PasswordClass = "PASSWORD";
        private static readonly TimeSpan MatchTimeout = TimeSpan.FromSeconds(1);

        private static readonly Regex PrivateKey = Pattern(
            @"-----BEGIN (?<kind>(?:(?:RSA |EC |DSA |OPENSSH |ENCRYPTED )?PRIVATE KEY|PGP PRIVATE KEY BLOCK))-----[\s\S]*?(?:-----END \k<kind>-----|\z)",
            RegexOptions.CultureInvariant);
        private static readonly Regex Authorization = Pattern(
            @"(\bAuthorization\s*:\s*(?:Bearer|Basic)\s+)([^\s,;]+)",
            RegexOptions.IgnoreCase | RegexOptions.Multiline | RegexOptions.CultureInvariant);
        private static readonly Regex SessionCookie = Pattern(
            @"(\b(?:session(?:id)?|connect\.sid|auth(?:_token)?|jwt|sid)\s*=\s*)([^;\s,]+)",
            RegexOptions.IgnoreCase | RegexOptions.CultureInvariant);
        private static readonly Regex ConnectionUri = Pattern(
            @"(\b[a-z][a-z0-9+.-]*://[^/\s:@]+:)([^@\s/]+)(@)",
            RegexOptions.IgnoreCase | RegexOptions.CultureInvariant);
        private static readonly Regex ProviderToken = Pattern(
            @"(?<![A-Za-z0-9])(?:sk-(?:proj-|ant-)?[A-Za-z0-9_-]{16,}|gh[pousr]_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,}|(?:AKIA|ASIA)[0-9A-Z]{16}|xox[baprs]-[A-Za-z0-9-]{10,}|npm_[A-Za-z0-9]{20,}|SG\.[A-Za-z0-9_-]{16,}\.[A-Za-z0-9_-]{16,}|shpat_[A-Fa-f0-9]{20,}|lin_api_[A-Za-z0-9]{20,}|ops_[A-Za-z0-9]{20,})(?![A-Za-z0-9])",
            RegexOptions.CultureInvariant);

        private const string Label =
            @"(?:password|passwd|pwd|api[_ -]?key|access[_ -]?token|refresh[_ -]?token|client[_ -]?secret|secret[_ -]?key|token|credential)";
        private static readonly Regex LabelledDoubleQuoted = Pattern(
            @"(\b" + Label + @"\b\s*[:=]\s*"")([^""\r\n]+)("")",
            RegexOptions.IgnoreCase | RegexOptions.CultureInvariant);
        private static readonly Regex LabelledSingleQuoted = Pattern(
            @"(\b" + Label + @"\b\s*[:=]\s*')([^'\r\n]+)(')",
            RegexOptions.IgnoreCase | RegexOptions.CultureInvariant);
        private static readonly Regex LabelledUnquoted = Pattern(
            @"(\b" + Label + @"\b\s*[:=]\s*)([^\r\n,;&]+)",
            RegexOptions.IgnoreCase | RegexOptions.CultureInvariant);

        private readonly Dictionary<string, int> counts = new Dictionary<string, int>
        {
            { PrivateKeyClass, 0 },
            { AuthorizationClass, 0 },
            { SessionCookieClass, 0 },
            { ConnectionSecretClass, 0 },
            { ProviderTokenClass, 0 },
            { LabelledSecretClass, 0 },
            { PasswordClass, 0 }
        };
        private readonly bool injectedFailure = string.Equals(
            Environment.GetEnvironmentVariable("WINDOWS_APPSHOTS_TEST_REDACTION_FAILURE"),
            "1", StringComparison.Ordinal);

        internal string Redact(string value, bool labelledSecret)
        {
            if (string.IsNullOrEmpty(value)) return value;
            if (injectedFailure)
                throw new CredentialRedactionException("Credential redaction was unavailable.");
            try
            {
                if (labelledSecret && !string.IsNullOrWhiteSpace(value))
                {
                    Count(LabelledSecretClass);
                    return Placeholder(LabelledSecretClass);
                }

                string output = ReplaceWhole(value, PrivateKey, PrivateKeyClass);
                output = ReplaceGroup(output, Authorization, 2, AuthorizationClass);
                output = ReplaceGroup(output, SessionCookie, 2, SessionCookieClass);
                output = ReplaceGroup(output, ConnectionUri, 2, ConnectionSecretClass);
                output = ReplaceWhole(output, ProviderToken, ProviderTokenClass);
                output = ReplaceLabelled(output, LabelledDoubleQuoted);
                output = ReplaceLabelled(output, LabelledSingleQuoted);
                output = ReplaceLabelled(output, LabelledUnquoted);
                return output;
            }
            catch (RegexMatchTimeoutException ex)
            {
                throw new CredentialRedactionException("Credential redaction timed out.", ex);
            }
            catch (CredentialRedactionException) { throw; }
            catch (Exception ex)
            {
                throw new CredentialRedactionException("Credential redaction failed.", ex);
            }
        }

        internal CredentialRedactionReceipt Complete()
        {
            return new CredentialRedactionReceipt
            {
                Succeeded = true,
                ReplacementCounts = new Dictionary<string, int>(counts),
                RawMatchesPersisted = false,
                VisualRedacted = false
            };
        }

        internal static bool IsCredentialLabel(params string[] values)
        {
            foreach (string value in values)
            {
                if (string.IsNullOrWhiteSpace(value)) continue;
                string normalized = Regex.Replace(value.ToLowerInvariant(), @"[^a-z0-9]", "");
                if (normalized.Contains("password") || normalized.Contains("passwd") ||
                    normalized.Contains("apikey") || normalized.Contains("accesstoken") ||
                    normalized.Contains("refreshtoken") || normalized.Contains("clientsecret") ||
                    normalized.Contains("secretkey") || normalized == "token" ||
                    normalized.EndsWith("tokeninput", StringComparison.Ordinal) ||
                    normalized.Contains("credentialvalue")) return true;
            }
            return false;
        }

        internal static string SanitizeDiagnostic(string value)
        {
            try { return new CredentialRedactor().Redact(value, false); }
            catch (Exception) { return "Credential-safe diagnostic unavailable."; }
        }

        private static Regex Pattern(string value, RegexOptions options)
        {
            return new Regex(value, options, MatchTimeout);
        }

        private string ReplaceWhole(string value, Regex regex, string credentialClass)
        {
            return regex.Replace(value, delegate(Match match)
            {
                Count(credentialClass);
                return Placeholder(credentialClass);
            });
        }

        private string ReplaceGroup(string value, Regex regex, int groupIndex, string credentialClass)
        {
            return regex.Replace(value, delegate(Match match)
            {
                Group group = match.Groups[groupIndex];
                Count(credentialClass);
                return match.Value.Substring(0, group.Index - match.Index) +
                    Placeholder(credentialClass) +
                    match.Value.Substring(group.Index - match.Index + group.Length);
            });
        }

        private string ReplaceLabelled(string value, Regex regex)
        {
            return regex.Replace(value, delegate(Match match)
            {
                string credentialClass = Regex.IsMatch(
                    match.Groups[1].Value, @"\b(?:password|passwd|pwd)\b",
                    RegexOptions.IgnoreCase, MatchTimeout)
                    ? PasswordClass : LabelledSecretClass;
                Count(credentialClass);
                return match.Groups[1].Value + Placeholder(credentialClass) + match.Groups[3].Value;
            });
        }

        private void Count(string credentialClass)
        {
            int count;
            counts.TryGetValue(credentialClass, out count);
            counts[credentialClass] = count + 1;
        }

        private static string Placeholder(string credentialClass)
        {
            return "[REDACTED:" + credentialClass + "]";
        }
    }
}
