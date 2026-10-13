#!/usr/bin/perl

use v5.36;

use IPC::Open2;
use JSON;

# qemu/target/i386/cpu.c, x86_cpu_initfn()
my $qemu_cpu_flag_alias_map = {
    cmp_legacy => 'cmp-legacy',
    ds_cpl => 'ds-cpl',
    ffxsr => 'fxsr-opt',
    fxsr_opt => 'fxsr-opt',
    'hv-apicv' => 'hv-avic',
    i64 => 'lm',
    kvm_nopiodelay => 'kvm-nopiodelay',
    kvm_mmu => 'kvm-mmu',
    kvm_asyncpf => 'kvm-asyncpf',
    kvm_asyncpf_int => 'kvm-asyncpf-int',
    kvm_steal_time => 'kvm-steal-time',
    kvm_pv_eoi => 'kvm-pv-eoi',
    kvm_pv_unhalt => 'kvm-pv-unhalt',
    kvm_poll_control => 'kvm-poll-control',
    lahf_lm => 'lahf-lm',
    lbr_fmt => 'lbr-fmt',
    nodeid_msr => 'nodeid-msr',
    nrip_save => 'nrip-save',
    pause_filter => 'pause-filter',
    pclmuldq => 'pclmulqdq',
    perfctr_core => 'perfctr-core',
    perfctr_nb => 'perfctr-nb',
    sse3 => 'pni',
    sse4_1 => 'sse4.1',
    sse4_2 => 'sse4.2',
    'sse4-1' => 'sse4.1',
    'sse4-2' => 'sse4.2',
    svm_lock => 'svm-lock',
    tsc_adjust => 'tsc-adjust',
    tsc_scale => 'tsc-scale',
    vmcb_clean => 'vmcb-clean',
    xd => 'nx',
};

# Static blacklist to be reviewed on QEMU bumps.
#
# Currently includes boolean properties from qom-list-properties that are neither CPUID
# flags ('-cpu help') nor Hyper-V enlightenments ('hv-*'). Entries excluded for other
# reasons are annotated inline.
my $filtered_props = {
    'max-x86_64-cpu' => {
        check => 1,
        'cpuid-0xb' => 1,
        enforce => 1,
        'fill-mtrr-mask' => 1,
        'host-cache-info' => 1,
        'host-phys-bits' => 1,
        hotpluggable => 1,
        hotplugged => 1,
        # Presence varies at built-time based on whether KVM is present (CONFIG_SYNDBG)
        # https://lore.proxmox.com/pve-devel/0fbeed5e-3d77-4126-828c-acdb04c109ff@proxmox.com/
        'hv-syndbg' => 1,
        kvm => 1,
        'kvm-pv-enforce-cpuid' => 1,
        'l3-cache' => 1,
        'legacy-cache' => 1,
        'legacy-multi-node' => 1,
        lmce => 1,
        migratable => 1,
        realized => 1,
        'start-powered-off' => 1,
        'tcg-cpuid' => 1,
        'vmware-cpuid-freq' => 1,
        'x-amd-topoext-features-only' => 1,
        'x-arch-cap-always-on' => 1,
        'x-consistent-cache' => 1,
        'x-force-cpuid-0x1f' => 1,
        'x-force-features' => 1,
        'x-l1-cache-per-thread' => 1,
        'x-migrate-error-code' => 1,
        'x-migrate-smi-count' => 1,
        'x-pdcm-on-even-without-pmu' => 1,
        'x-vendor-cpuid-only' => 1,
        'x-vendor-cpuid-only-v2' => 1,
        'xen-vapic' => 1,
    },
};

sub print_flags($qemu_bin, $typename) {
    die "Unknown typename, must be one of '" . join("', '", keys $filtered_props->%*) . "'\n"
        if !defined($filtered_props->{$typename});

    my $pid = open2(
        my $out,
        my $in,
        $qemu_bin,
        '-machine',
        'none',
        '-display',
        'none',
        '-S',
        '-qmp',
        'stdio',
        '-nodefaults',
    );

    my $qmp = sub ($cmd, %args) {
        print $in encode_json({ execute => $cmd, %args ? (arguments => \%args) : () }), "\n";
        while (my $line = <$out>) {
            my $msg = decode_json($line);
            next if $msg->{event};
            return $msg->{return} if exists($msg->{return});
            die "QMP error: " . encode_json($msg->{error}) if $msg->{error};
        }
    };

    my $flags = {};
    my $greeting = <$out>;
    my $decoded_greeting = decode_json($greeting);
    die "Unexpected QMP greeting: $greeting\n" if !exists($decoded_greeting->{QMP});

    $qmp->('qmp_capabilities');
    my $props = $qmp->('qom-list-properties', typename => $typename);
    for my $qo ($props->@*) {
        next if $qo->{type} ne 'bool' || defined($filtered_props->{$typename}->{$qo->{name}});
        my $resolved_name = $qemu_cpu_flag_alias_map->{$qo->{name}} // $qo->{name};
        $flags->{$resolved_name} = 1;
    }
    $qmp->('quit');
    waitpid($pid, 0);

    my @flags = sort keys $flags->%*;
    print join("\n", @flags) . "\n";
}

my ($qemu_bin, $typename) = @ARGV;
print_flags($qemu_bin, $typename);
