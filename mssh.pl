#!/usr/bin/perl
use strict;
use warnings;
use File::Spec;
use Env;
my $path_curf = File::Spec->rel2abs(__FILE__);
my ($vol, $path, $file) = File::Spec->splitpath($path_curf);


my $timeout = 30;
my $MAXPROC = 21;
if(scalar(@ARGV)<2){
        print "Usage: $0 runCmd  \"cmd\"\n";
        print "Usage: $0 get srcpath dstpath\n";
        print "Usage: $0 put srcpath dstpath\n";
        exit 0;
}
my $method = $ARGV[0];

my $start = time;
if(!open(FILE,'host.ini')){
        print "open host.ini failed\n";
        return -1;
}
my @lines = <FILE>;
close(FILE);

my $lockFile = 'counter.lock';
print "Start: Lock file is: $lockFile\n";
my $procs = scalar(@lines);
if(-e "$lockFile"){
        print "请确认是否有其他人在执行本操作,否则请删除$lockFile文件\n";
        exit(-1);
}

my @pids = ();
my $procNum = 0;
for (my $i=0; $i < $procs ;$i++) {
        my $line = $lines[$i];
        chomp($line);
	next if($line =~ /^#/);
        my ($name,$ip,$rootPass) = split /,/,$line;
        my $cmd;
        my $sshCmd;
	my $retPipe = pipe(READPIPE,WRITEPIPE);
        my $pid = fork();
        if($pid == 0){
		close(READPIPE);
                if($method eq 'runCmd'){
                        shift(@ARGV);
                        $cmd = join ' ',@ARGV;
                        $sshCmd = "ssh  -o 'StrictHostKeyChecking no' -o ConnectTimeout=$timeout $ip \"$cmd\" 2>>error.log";
                }elsif($method eq 'get'){
                        my $src = $ARGV[1];
                        my $dst = $ARGV[2];
                        $sshCmd = "scp -rp  -o 'StrictHostKeyChecking no' -o ConnectTimeout=$timeout $ip:$src $dst.$name 2>error.log";
			print WRITEPIPE "$sshCmd\n";
                }elsif($method eq 'put'){
                        my $src = $ARGV[1];
                        my $dst = $ARGV[2];
                        $sshCmd = "scp -rp  -o 'StrictHostKeyChecking no' -o ConnectTimeout=$timeout $src $ip:$dst 2>error.log";
			print WRITEPIPE "$sshCmd\n";
		}else{
			print "has not this method:  $method\n";
			exit 1;
		}
                my @out;
                @out  = `$sshCmd`;
		if($? != 0){
               		print WRITEPIPE $sshCmd."   error=$?\n";
		}
	        while(-f "$lockFile"){
       			select(undef,undef,undef,0.1);
        	}
		open(LOCKFILE,">$lockFile");
                my $count = 0;
                foreach my $inLine (@out) {
                        if($inLine !~ /Authorized uses only/){
                                print WRITEPIPE "$name $ip:  $inLine";
                                $count++;
                        }
                }
		close(LOCKFILE);
		unlink("$lockFile");
                exit 0;
        }else{
		close(WRITEPIPE);
		my $line;
		while($line = <READPIPE>){
			print $line;
		}
                $procNum++;
                push(@pids,$pid);
        }
        if($procNum >= $MAXPROC ){
                foreach my $pid (@pids){
                         waitpid($pid,0);
                }
                $procNum = 0;
                @pids = ();
        }
}
        foreach my $pid (@pids){
                     waitpid($pid,0);
        }
my $elapse=time()-$start;
print "End, elapse $elapse secondes\n";
