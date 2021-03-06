defmodule Benchee.System do
  @moduledoc """
  Provides information about the system the benchmarks are run on.
  """

  alias Benchee.Suite

  @doc """
  Adds system information to the suite (currently elixir and erlang versions).
  """
  @spec system(Suite.t) :: Suite.t
  def system(suite = %Suite{}) do
    system_info = %{elixir: elixir(),
                    erlang: erlang(),
                    num_cores: num_cores(),
                    os: os(),
                    available_memory: available_memory(),
                    cpu_speed: cpu_speed()}
    %Suite{suite | system: system_info}
  end

  @doc """
  Returns current Elixir version in use.
  """
  def elixir, do: System.version()

  @doc """
  Returns the current erlang/otp version in use.
  """
  def erlang do
    otp_release = :erlang.system_info(:otp_release)
    file = Path.join([:code.root_dir, "releases", otp_release , "OTP_VERSION"])
    case File.read(file) do
      {:ok, version}    -> String.trim(version)
      {:error, reason}  ->
        IO.puts "Error trying to dermine erlang version #{reason}"
    end
  end

  @doc """
  Returns the number of cores available for the currently running VM.
  """
  def num_cores do
    System.schedulers_online()
  end

  @doc """
  Returns an atom representing the platform the VM is running on.
  """
  def os do
    {_, name} = :os.type()
    os(name)
  end
  defp os(:darwin), do: :macOS
  defp os(:nt), do: :Windows
  defp os(_), do: :Linux

  @doc """
  Returns a string with detailed information about the CPU the benchmarks are
  being performed on.
  """
  def cpu_speed, do: cpu_speed(os())

  defp cpu_speed(:Windows) do
    parse_cpu_for(:Windows, system_cmd("WMIC", ["CPU", "GET", "NAME"]))
  end
  defp cpu_speed(:macOS) do
    parse_cpu_for(:macOS, system_cmd("sysctl", ["-n", "machdep.cpu.brand_string"]))
  end
  defp cpu_speed(:Linux) do
    parse_cpu_for(:Linux, system_cmd("cat", ["/proc/cpuinfo"]))
  end

  @linux_cpuinfo_regex ~r/model name.*:([\w \(\)\-\@\.]*)/i

  def parse_cpu_for(_, "N/A"), do: "N/A"
  def parse_cpu_for(:Windows, raw_output) do
    "Name" <> cpu_info = raw_output
    String.trim(cpu_info)
  end
  def parse_cpu_for(:macOS, raw_output), do: String.trim(raw_output)
  def parse_cpu_for(:Linux, raw_output) do
    match_info = Regex.run(@linux_cpuinfo_regex,
                           raw_output,
                           capture: :all_but_first)
    case match_info do
      [cpu_info] -> String.trim(cpu_info)
      _          -> "Unrecognized processor"
    end
  end

  @doc """
  Returns an integer with the total number of available memory on the machine
  running the benchmarks.
  """
  def available_memory, do: available_memory(os())

  defp available_memory(:Windows) do
    parse_memory_for(
      :Windows,
      system_cmd("WMIC", ["COMPUTERSYSTEM", "GET", "TOTALPHYSICALMEMORY"])
    )
  end
  defp available_memory(:macOS) do
    parse_memory_for(:macOS, system_cmd("sysctl", ["-n", "hw.memsize"]))
  end
  defp available_memory(:Linux) do
    parse_memory_for(:Linux, system_cmd("cat", ["/proc/meminfo"]))
  end

  @kilobyte_to_gigabyte 1024 * 1024
  @byte_to_gigabyte 1024 * @kilobyte_to_gigabyte

  defp parse_memory_for(_, "N/A"), do: "N/A"
  defp parse_memory_for(:Windows, raw_output) do
    [memory] = Regex.run(~r/\d+/, raw_output)
    {memory, _} = Integer.parse(memory)
    format_memory(memory, @byte_to_gigabyte)
  end
  defp parse_memory_for(:macOS, raw_output) do
    {memory, _} = Integer.parse(raw_output)
    format_memory(memory, @byte_to_gigabyte)
  end
  defp parse_memory_for(:Linux, raw_output) do
    ["MemTotal:" <> memory] = Regex.run(~r/MemTotal.*kB/, raw_output)
    {memory, _} = memory
                  |> String.trim()
                  |> String.trim_trailing(" kB")
                  |> Integer.parse
    format_memory(memory, @kilobyte_to_gigabyte)
  end

  defp format_memory(memory, coefficient), do: "#{Float.round(memory / coefficient, 2)} GB"

  def system_cmd(cmd, args, system_func \\ &System.cmd/2) do
    {output, exit_code} = system_func.(cmd, args)
    if exit_code > 0 do
      IO.puts("Something went wrong trying to get system information:")
      IO.puts(output)
      "N/A"
    else
      output
    end
  end
end
