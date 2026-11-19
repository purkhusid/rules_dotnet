namespace OverridingApp
{
    public static class Program
    {
        public static void Main()
        {
            System.Console.WriteLine(typeof(System.Formats.Asn1.AsnReader).Assembly.GetName().Version);
        }
    }
}
