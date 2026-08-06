using System;
using System.Drawing;
using System.Runtime.InteropServices;
using System.Threading;
using System.Windows.Forms;

internal sealed class HangingAccessibleControl : Control
{
    protected override AccessibleObject CreateAccessibilityInstance()
    {
        return new HangingAccessibleObject(this);
    }

    private sealed class HangingAccessibleObject : ControlAccessibleObject
    {
        internal HangingAccessibleObject(Control owner) : base(owner) { }

        public override string Name
        {
            get
            {
                Thread.Sleep(10000);
                return "Synthetic delayed accessibility provider";
            }
        }
    }
}

internal sealed class FixtureWindow : Form
{
    [DllImport("user32.dll")]
    private static extern bool SetForegroundWindow(IntPtr hwnd);

    internal FixtureWindow(string instance)
    {
        Text = "Windows AppShots Acceptance Fixture - " + instance +
            " - client_secret=APPSHOTS_TITLE_SECRET_SENTINEL";
        Width = 900;
        Height = 700;
        StartPosition = FormStartPosition.CenterScreen;

        Label heading = new Label
        {
            Text = "Sample semantic acceptance",
            AccessibleName = "Sample semantic acceptance heading",
            Font = new Font(SystemFonts.DefaultFont.FontFamily, 18),
            Location = new Point(30, 25),
            AutoSize = true
        };
        TextBox message = new TextBox
        {
            Name = "message",
            AccessibleName = "Synthetic message",
            Text = "Synthetic sample action is ready",
            Location = new Point(30, 85),
            Width = 520
        };
        TextBox password = new TextBox
        {
            Name = "password",
            AccessibleName = "Password",
            Text = "PASSWORD_VALUE_MUST_NOT_APPEAR",
            UseSystemPasswordChar = true,
            Location = new Point(30, 130),
            Width = 280
        };
        Button send = new Button
        {
            Name = "send",
            AccessibleName = "Send synthetic action",
            Text = "Send",
            Location = new Point(30, 180),
            Width = 180
        };
        CheckBox safe = new CheckBox
        {
            AccessibleName = "Synthetic data only",
            Text = "Synthetic data only",
            Checked = true,
            Location = new Point(30, 235),
            Width = 220
        };
        TextBox credentials = new TextBox
        {
            Name = "synthetic-config",
            AccessibleName = "Synthetic configuration samples",
            Multiline = true,
            Text =
                "Authorization: Bearer sk-proj-APPSHOTS_AUTHORIZATION_SECRET_SENTINEL_123456789\r\n" +
                "sessionid=APPSHOTS_SESSION_COOKIE_SECRET_SENTINEL\r\n" +
                "postgres://alice:APPSHOTS_CONNECTION_SECRET_SENTINEL@db.example/app\r\n" +
                "sk-proj-APPSHOTS_PROVIDER_TOKEN_SECRET_SENTINEL_123456789\r\n" +
                "client_secret=APPSHOTS_LABELLED_SECRET_SENTINEL\r\n" +
                "password=APPSHOTS_PASSWORD_SECRET_SENTINEL\r\n" +
                "-----BEGIN PRIVATE KEY-----\r\n" +
                "APPSHOTS_PRIVATE_KEY_SECRET_SENTINEL\r\n" +
                "-----END PRIVATE KEY-----\r\n" +
                "public_key=APPSHOTS_PUBLIC_KEY_NEARMISS\r\n" +
                "application_id=APPSHOTS_APPLICATION_ID_NEARMISS\r\n" +
                "sha256=APPSHOTS_HASH_NEARMISS\r\n" +
                "-----BEGIN CERTIFICATE----- APPSHOTS_CERTIFICATE_NEARMISS -----END CERTIFICATE-----\r\n" +
                "Name: Synthetic Person; phone: +61 400 000 000; test-card: 4111111111111111\r\n" +
                "government-id=APPSHOTS_GOV_ID_NEARMISS customer-record=APPSHOTS_CUSTOMER_NEARMISS\r\n" +
                "ordinary confidential prose and entropy YWJjZGVmZ2hpamtsbW5vcHFyc3R1dnd4eXo\r\n" +
                "contact@example.test C:\\synthetic\\fixture.txt 123e4567-e89b-12d3-a456-426614174000",
            Location = new Point(30, 285),
            Width = 790,
            Height = 280,
            ScrollBars = ScrollBars.Vertical
        };
        Controls.Add(heading);
        Controls.Add(message);
        Controls.Add(password);
        Controls.Add(send);
        Controls.Add(safe);
        Controls.Add(credentials);
        if (instance == "Hanging")
        {
            Controls.Add(new HangingAccessibleControl
            {
                Name = "hanging-provider",
                Location = new Point(30, 585),
                Size = new Size(250, 50),
                TabStop = true
            });
        }

        Shown += delegate
        {
            SetForegroundWindow(Handle);
            Console.Out.WriteLine(Handle.ToInt64());
            Console.Out.Flush();
        };
    }

    [STAThread]
    private static void Main(string[] args)
    {
        Application.EnableVisualStyles();
        Application.SetCompatibleTextRenderingDefault(false);
        string instance = args.Length > 0 ? args[0] : "Primary";
        Application.Run(new FixtureWindow(instance));
    }
}
