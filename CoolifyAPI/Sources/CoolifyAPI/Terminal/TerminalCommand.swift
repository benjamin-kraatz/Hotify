import Foundation

/// The shell lines the terminal runs on a server over SSH.
public enum TerminalCommand {
    /// The shell Coolify's own terminal starts: the profile, then the user's shell, else `sh` for an image without
    /// one.
    public static let loginShell =
        #"PATH=$PATH:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin && "#
        + #"if [ -f ~/.profile ]; then . ~/.profile; fi && "#
        + #"if [ -n "$SHELL" ] && [ -x "$SHELL" ]; then exec $SHELL; else sh; fi"#

    /// Opens the login shell inside a running container.
    public static func shell(inContainer name: String, usesSudo: Bool) -> String {
        (usesSudo ? "sudo " : "") + "docker exec -it \(Shell.quote(name)) sh -c \(Shell.quote(loginShell))"
    }

    /// Adds a public key to the SSH user's `authorized_keys`, once. Creates the file with private permissions if it's
    /// missing, and starts a new line when the file doesn't end in one.
    public static func installKey(_ publicKey: String) -> String {
        let key = Shell.quote(publicKey)
        let file = "~/.ssh/authorized_keys"
        return [
            "umask 077",
            "mkdir -p ~/.ssh",
            "touch \(file)",
            #"if [ -s \#(file) ] && [ -n "$(tail -c1 \#(file))" ]; then echo >> \#(file); fi"#,
            "grep -qxF \(key) \(file) || echo \(key) >> \(file)",
        ].joined(separator: " && ")
    }

    /// The same, short enough for a person to read before they paste it on the server.
    public static func addKeyByHand(_ publicKey: String) -> String {
        "echo \(Shell.quote(publicKey)) >> ~/.ssh/authorized_keys"
    }
}
